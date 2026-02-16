import logging
import numpy as np
from typing import Optional

from iblrig.base_choice_world import ChoiceWorldSession
from iblrig.pydantic_definitions import TrialDataModel
from pydantic import NonNegativeFloat, NonNegativeInt

logger = logging.getLogger('iblrig.task')

class GNGStage0TrialData(TrialDataModel):
    trial_num: NonNegativeInt
    reward_amount: NonNegativeFloat
    response_time: Optional[float] = np.nan

class Session(ChoiceWorldSession):
    """
    Go/No-Go Stage 0: Any movement during response period is rewarded.
    """
    TrialDataModel = GNGStage0TrialData
    protocol_name = 'gng_stage0'

    def __init__(self, *args, reward_amount_ul=3.0, response_period_s=3.0, iti_s=0.1, **kwargs):
        super().__init__(*args, **kwargs)
        self.task_params['REWARD_AMOUNT_UL'] = reward_amount_ul
        self.task_params['RESPONSE_PERIOD_S'] = response_period_s
        self.task_params['ITI_S'] = iti_s

    @staticmethod
    def extra_parser():
        parser = super(Session, Session).extra_parser()
        parser.add_argument(
            '--reward_amount_ul',
            dest='reward_amount_ul',
            default=3.0,
            type=float,
            help='reward volume in microliters',
        )
        parser.add_argument(
            '--response_period_s',
            dest='response_period_s',
            default=3.0,
            type=float,
            help='response period in seconds',
        )
        parser.add_argument(
            '--iti_s',
            dest='iti_s',
            default=0.1,
            type=float,
            help='inter-trial interval in seconds',
        )
        return parser

    def start_hardware(self):
        self.start_mixin_bpod()
        self.start_mixin_valve()
        self.start_mixin_rotary_encoder()

    def get_state_machine_trial(self, i):
        sma = self._instantiate_state_machine(trial_number=i)
        
        # stimulus trigger pulse (1ms)
        stim_trigger_time = 0.001

        if i == 0:
            # First trial start camera/external recording
            sma.add_state(
                state_name='trial_start',
                state_timer=0,
                state_change_conditions={'Tup': 'reset_rotary_encoder'},
                output_actions=[('BNC1', 255)], # Toggle/Pulse for start
            )

        sma.add_state(
            state_name='reset_rotary_encoder',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'response_period'},
        )

        sma.add_state(
            state_name='response_period',
            state_timer=self.task_params.RESPONSE_PERIOD_S,
            output_actions=[('BNC1', 255)], # Stimulus ON signal
            state_change_conditions={
                'Tup': 'ITI',
                self.movement_left: 'reward',
                self.movement_right: 'reward',
            },
        )

        sma.add_state(
            state_name='reward',
            state_timer=self.reward_time,
            output_actions=[('Valve1', 255), ('BNC1', 255)], # Keep Stim ON signal or toggle?
            # In legacy it was (BNC1, 1). If we want it ON during reward too, we keep it.
            state_change_conditions={'Tup': 'ITI'},
        )

        sma.add_state(
            state_name='ITI',
            state_timer=self.task_params.ITI_S,
            output_actions=[], # BNC1 goes low here
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
        response_time = reward_state[0][0] - event_timestamps['response_period'][0][0] if is_hit else np.nan

        self.session_info.TOTAL_WATER_DELIVERED += trial_reward
        self.session_info.NTRIALS += 1 

        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'reward_amount'] = trial_reward
        self.trials_table.at[self.trial_num, 'response_time'] = np.round(response_time, 3) if not np.isnan(response_time) else np.nan

        self.save_trial_data_to_json(bpod_data)
        # self.save_trials_table_to_csv() # Base class might handle this or we can add it

    def next_trial(self):
        self.trial_num += 1
        self.draw_next_trial_info()

if __name__ == '__main__':
    kwargs = iblrig.misc.get_task_arguments(parents=[Session.extra_parser()])
    sess = Session(**kwargs)
    sess.run()
