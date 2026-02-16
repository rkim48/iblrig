import logging
import random
import numpy as np
from typing import Optional, List

from iblrig.base_choice_world import ChoiceWorldSession
from iblrig.pydantic_definitions import TrialDataModel
from pydantic import NonNegativeFloat, NonNegativeInt
import iblrig.misc

logger = logging.getLogger('iblrig.task')

class MoCSTrialData(TrialDataModel):
    trial_num: NonNegativeInt
    reward_amount: NonNegativeFloat
    response_time: Optional[float] = np.nan
    quiescent_period: float
    quiescent_period_violations: List[float]
    outcome: str

class Session(ChoiceWorldSession):
    """
    Method of Constant Stimuli (MoCS) Task:
    Includes PSP stillness enforcement and BNC1 GlobalCounter for trial assessment.
    """
    TrialDataModel = MoCSTrialData
    protocol_name = 'mocs'

    def __init__(self, *args, reward_amount_ul=3.0, psp_range=[0.2, 0.5], response_period_s=3.0, iti_range=[2.0, 5.0], **kwargs):
        super().__init__(*args, **kwargs)
        self.task_params['REWARD_AMOUNT_UL'] = reward_amount_ul
        self.task_params['PSP_RANGE'] = psp_range
        self.task_params['RESPONSE_PERIOD_S'] = response_period_s
        self.task_params['ITI_RANGE'] = iti_range
        self.quiescent_period_violations = []

    @staticmethod
    def extra_parser():
        parser = super(Session, Session).extra_parser()
        parser.add_argument('--reward_amount_ul', default=3.0, type=float)
        parser.add_argument('--psp_range', default=[0.2, 0.5], type=float, nargs=2)
        parser.add_argument('--response_period_s', default=3.0, type=float)
        parser.add_argument('--iti_range', default=[2.0, 5.0], type=float, nargs=2)
        return parser

    def start_hardware(self):
        self.start_mixin_bpod()
        self.start_mixin_valve()
        self.start_mixin_rotary_encoder()

    def get_state_machine_trial(self, i):
        sma = self._instantiate_state_machine(trial_number=i)
        
        # Configure GlobalCounter 1 to count 1 pulse on BNC1 Input
        sma.set_global_counter(counter_number=1, target_event='BNC1High', threshold=1)

        sma.add_state(
            state_name='trial_start',
            state_timer=0,
            state_change_conditions={'Tup': 'reset_rotary_encoder_PSP'},
            output_actions=[], 
        )

        sma.add_state(
            state_name='reset_rotary_encoder_PSP',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'quiescent_period'},
        )

        sma.add_state(
            state_name='quiescent_period',
            state_timer=self.quiescent_period,
            output_actions=[],
            state_change_conditions={
                'Tup': 'stim_on',
                self.movement_left: 'reset_rotary_encoder_violation',
                self.movement_right: 'reset_rotary_encoder_violation',
            },
        )

        sma.add_state(
            state_name='reset_rotary_encoder_violation',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'quiescent_period'},
        )

        sma.add_state(
            state_name='stim_on',
            state_timer=0.001,
            output_actions=[('BNC1', 255)], # Pulse Stim ON
            state_change_conditions={'Tup': 'response_period'},
        )

        sma.add_state(
            state_name='response_period',
            state_timer=self.task_params.RESPONSE_PERIOD_S,
            output_actions=[],
            state_change_conditions={
                'Tup': 'no_go',
                self.movement_left: 'wheel_turn',
                self.movement_right: 'wheel_turn',
            },
        )

        sma.add_state(
            state_name='wheel_turn',
            state_timer=0.001,
            output_actions=[('BNC1', 255)], # Pulse BNC1 to listen for response
            state_change_conditions={'Tup': 'listen_for_BNC'},
        )

        sma.add_state(
            state_name='listen_for_BNC',
            state_timer=0.01, # Wait 10ms for return signal
            output_actions=[],
            state_change_conditions={
                'GlobalCounter1_End': 'no_reward', # Signal received = NoGo/Error
                'Tup': 'reward',                   # No signal = Go/Success
            },
        )

        sma.add_state(
            state_name='reward',
            state_timer=self.reward_time,
            output_actions=[('Valve1', 255)],
            state_change_conditions={'Tup': 'ITI'},
        )

        sma.add_state(
            state_name='no_reward',
            state_timer=0,
            output_actions=[],
            state_change_conditions={'Tup': 'ITI'},
        )

        sma.add_state(
            state_name='no_go',
            state_timer=0,
            output_actions=[('BNC1', 255)], # End stim session if NoGo reached
            state_change_conditions={'Tup': 'ITI'},
        )

        sma.add_state(
            state_name='ITI',
            state_timer=self.iti_duration,
            output_actions=[],
            state_change_conditions={'Tup': 'exit_state'},
        )

        sma.add_state(
            state_name='exit_state',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'exit'},
        )

        return sma

    def trial_completed(self, bpod_data):
        event_timestamps = bpod_data['States timestamps']
        
        if not np.isnan(event_timestamps.get('reward', [[np.nan, np.nan]])[0][0]):
            self.trials_table.at[self.trial_num, 'outcome'] = 'hit'
            trial_reward = self.default_reward_amount
        elif not np.isnan(event_timestamps.get('no_reward', [[np.nan, np.nan]])[0][0]):
            self.trials_table.at[self.trial_num, 'outcome'] = 'miss'
            trial_reward = 0.0
        else:
            self.trials_table.at[self.trial_num, 'outcome'] = 'no_go'
            trial_reward = 0.0

        is_hit = self.trials_table.at[self.trial_num, 'outcome'] == 'hit'
        response_time = event_timestamps['wheel_turn'][0][0] - event_timestamps['response_period'][0][0] if not np.isnan(event_timestamps['wheel_turn'][0][0]) else np.nan

        # PSP violations
        violations = event_timestamps.get('reset_rotary_encoder_violation', [])
        self.quiescent_period_violations = [v[0] for v in violations]

        self.session_info.TOTAL_WATER_DELIVERED += trial_reward
        self.session_info.NTRIALS += 1 

        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'reward_amount'] = trial_reward
        self.trials_table.at[self.trial_num, 'response_time'] = np.round(response_time, 3) if not np.isnan(response_time) else np.nan
        self.trials_table.at[self.trial_num, 'quiescent_period'] = self.quiescent_period
        self.trials_table.at[self.trial_num, 'quiescent_period_violations'] = self.quiescent_period_violations

        self.save_trial_data_to_json(bpod_data)

    def next_trial(self):
        self.trial_num += 1
        self.draw_next_trial_info()

    def draw_next_trial_info(self):
        self.quiescent_period = random.uniform(*self.task_params.PSP_RANGE)
        self.iti_duration = random.uniform(*self.task_params.ITI_RANGE)
        super().draw_next_trial_info()

if __name__ == '__main__':
    kwargs = iblrig.misc.get_task_arguments(parents=[Session.extra_parser()])
    sess = Session(**kwargs)
    sess.run()
