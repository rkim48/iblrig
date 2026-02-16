import logging
import random
import numpy as np
from typing import Optional, List

from iblrig.base_choice_world import ChoiceWorldSession
from iblrig.pydantic_definitions import TrialDataModel
from pydantic import NonNegativeFloat, NonNegativeInt
import iblrig.misc

logger = logging.getLogger('iblrig.task')

class GNGStage1TrialData(TrialDataModel):
    trial_num: NonNegativeInt
    reward_amount: NonNegativeFloat
    response_time: Optional[float] = np.nan
    quiescent_period: float
    quiescent_period_violations: List[float]

class Session(ChoiceWorldSession):
    """
    Go/No-Go Stage 1: Randomized PSP with stillness enforcement.
    Any move during PSP resets the timer.
    """
    TrialDataModel = GNGStage1TrialData
    protocol_name = 'gng_stage1'

    def __init__(self, *args, reward_amount_ul=3.0, psp_range=[0.2, 0.5], response_period_s=3.0, iti_s=2.0, **kwargs):
        super().__init__(*args, **kwargs)
        self.task_params['REWARD_AMOUNT_UL'] = reward_amount_ul
        self.task_params['PSP_RANGE'] = psp_range
        self.task_params['RESPONSE_PERIOD_S'] = response_period_s
        self.task_params['ITI_S'] = iti_s
        self.quiescent_period_violations = []

    @staticmethod
    def extra_parser():
        parser = super(Session, Session).extra_parser()
        parser.add_argument('--reward_amount_ul', default=3.0, type=float)
        parser.add_argument('--psp_range', default=[0.2, 0.5], type=float, nargs=2)
        parser.add_argument('--response_period_s', default=3.0, type=float)
        parser.add_argument('--iti_s', default=2.0, type=float)
        return parser

    def start_hardware(self):
        self.start_mixin_bpod()
        self.start_mixin_valve()
        self.start_mixin_rotary_encoder()

    def get_state_machine_trial(self, i):
        sma = self._instantiate_state_machine(trial_number=i)
        
        # BNC1: Stimulus control
        # BNC2: Imaging/Recording control

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
                'Tup': 'stop_stim_no_reward',
                self.movement_left: 'stop_stim_reward',
                self.movement_right: 'stop_stim_reward',
            },
        )

        sma.add_state(
            state_name='stop_stim_reward',
            state_timer=0.001,
            output_actions=[('BNC1', 255)], # Pulse Stim OFF
            state_change_conditions={'Tup': 'reward'},
        )

        sma.add_state(
            state_name='stop_stim_no_reward',
            state_timer=0.001,
            output_actions=[('BNC1', 255)], # Pulse Stim OFF
            state_change_conditions={'Tup': 'ITI'},
        )

        sma.add_state(
            state_name='reward',
            state_timer=self.reward_time,
            output_actions=[('Valve1', 255)],
            state_change_conditions={'Tup': 'ITI'},
        )

        sma.add_state(
            state_name='ITI',
            state_timer=self.task_params.ITI_S,
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
        reward_state = event_timestamps.get('reward', [[np.nan, np.nan]])
        is_hit = not np.isnan(reward_state[0][0])
        
        trial_reward = self.default_reward_amount if is_hit else 0.0
        
        if is_hit:
            response_time = event_timestamps['stop_stim_reward'][0][0] - event_timestamps['response_period'][0][0]
        else:
            response_time = np.nan

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
        super().draw_next_trial_info()

if __name__ == '__main__':
    kwargs = iblrig.misc.get_task_arguments(parents=[Session.extra_parser()])
    sess = Session(**kwargs)
    sess.run()
