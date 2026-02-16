import logging
import numpy as np
import random
from typing import Optional, List

from iblrig.base_choice_world import ChoiceWorldSession
from iblrig.pydantic_definitions import TrialDataModel
from pydantic import NonNegativeFloat, NonNegativeInt
import iblrig.misc

logger = logging.getLogger('iblrig.task')

class StaircaseTrialData(TrialDataModel):
    trial_num: NonNegativeInt
    reward_amount: NonNegativeFloat
    response_time: Optional[float] = np.nan
    current: float
    reversal: bool
    channel: int
    outcome: str

class Session(ChoiceWorldSession):
    """
    Staircase Paradigm:
    1-up/1-down staircase to determine stimulation thresholds.
    Loops through multiple stimulation channels.
    """
    TrialDataModel = StaircaseTrialData
    protocol_name = 'staircase'

    def __init__(self, *args, 
                 init_current=10.0, 
                 max_current=20.0, 
                 min_current=1.0, 
                 init_step=3.0, 
                 step_size=1.0, 
                 max_reversals=9, 
                 max_trials_per_ch=25, 
                 channels=[1, 2, 3], # Default Ripple channels
                 response_period_s=0.95, 
                 iti_s=2.0, 
                 **kwargs):
        super().__init__(*args, **kwargs)
        
        # Staircase parameters
        self.task_params.update({
            'INIT_CURRENT': init_current,
            'MAX_CURRENT': max_current,
            'MIN_CURRENT': min_current,
            'INIT_STEP': init_step,
            'STEP_SIZE': step_size,
            'MAX_REVERSALS': max_reversals,
            'MAX_TRIALS_PER_CH': max_trials_per_ch,
            'CHANNELS_LIST': channels,
            'RESPONSE_PERIOD_S': response_period_s,
            'ITI_S': iti_s,
        })

        # State variables
        self.channels_to_test = list(channels)
        random.shuffle(self.channels_to_test)
        
        self.current_ch_idx = 0
        self.trial_in_ch = 0
        self.current_value = init_current
        self.reversal_count = 0
        self.last_outcome = None # 'hit' or 'miss'
        self.channel_done = False

    @staticmethod
    def extra_parser():
        parser = super(Session, Session).extra_parser()
        parser.add_argument('--init_current', default=10.0, type=float)
        parser.add_argument('--max_current', default=20.0, type=float)
        parser.add_argument('--init_step', default=3.0, type=float)
        parser.add_argument('--step_size', default=1.0, type=float)
        parser.add_argument('--max_reversals', default=9, type=int)
        parser.add_argument('--max_trials_per_ch', default=25, type=int)
        parser.add_argument('--channels', default=[1, 2, 3], type=int, nargs='+')
        return parser

    def start_hardware(self):
        self.start_mixin_bpod()
        self.start_mixin_valve()
        self.start_mixin_rotary_encoder()

    def get_state_machine_trial(self, i):
        sma = self._instantiate_state_machine(trial_number=i)
        
        # BNC1: Stimulus control (Ripple SMA2)
        # BNC2: Imaging/Recording control

        sma.add_state(
            state_name='trial_start',
            state_timer=0,
            state_change_conditions={'Tup': 'reset_rotary_encoder'},
            output_actions=[], 
        )

        sma.add_state(
            state_name='reset_rotary_encoder',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'stim_on'},
        )

        sma.add_state(
            state_name='stim_on',
            state_timer=0.001,
            output_actions=[('BNC1', 255)], # Pulse Stim ON (Ripple starts)
            state_change_conditions={'Tup': 'response_period'},
        )

        sma.add_state(
            state_name='response_period',
            state_timer=self.task_params.RESPONSE_PERIOD_S,
            output_actions=[],
            state_change_conditions={
                'Tup': 'miss',                 # No movement detected
                self.movement_left: 'hit',     # Any movement = Hit
                self.movement_right: 'hit',
            },
        )

        sma.add_state(
            state_name='hit',
            state_timer=0,
            output_actions=[('BNC1', 255)], # Pulse BNC1 to stop stimulation early
            state_change_conditions={'Tup': 'reward'},
        )

        sma.add_state(
            state_name='reward',
            state_timer=self.reward_time,
            output_actions=[('Valve1', 255)],
            state_change_conditions={'Tup': 'ITI'},
        )

        sma.add_state(
            state_name='miss',
            state_timer=0,
            output_actions=[('BNC1', 255)], # Pulse BNC1 to ensure stim stops
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
        
        is_hit = not np.isnan(event_timestamps.get('hit', [[np.nan, np.nan]])[0][0])
        outcome = 'hit' if is_hit else 'miss'
        
        trial_reward = self.default_reward_amount if is_hit else 0.0
        response_time = (event_timestamps['hit'][0][0] - event_timestamps['response_period'][0][0]) if is_hit else np.nan

        # Staircase logic: reversal tracking
        is_reversal = False
        if self.last_outcome is not None and self.last_outcome != outcome:
            self.reversal_count += 1
            is_reversal = True
        
        self.last_outcome = outcome

        # Save data
        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'reward_amount'] = trial_reward
        self.trials_table.at[self.trial_num, 'response_time'] = np.round(response_time, 3) if not np.isnan(response_time) else np.nan
        self.trials_table.at[self.trial_num, 'current'] = self.current_value
        self.trials_table.at[self.trial_num, 'reversal'] = is_reversal
        self.trials_table.at[self.trial_num, 'channel'] = self.channels_to_test[self.current_ch_idx]
        self.trials_table.at[self.trial_num, 'outcome'] = outcome

        self.session_info.TOTAL_WATER_DELIVERED += trial_reward
        self.session_info.NTRIALS += 1 

        self.save_trial_data_to_json(bpod_data)

        # Update Staircase state for next trial
        curr_step = self.task_params.INIT_STEP if self.reversal_count < 3 else self.task_params.STEP_SIZE
        
        if is_hit:
            self.current_value = max(self.current_value - curr_step, self.task_params.MIN_CURRENT)
        else:
            self.current_value = min(self.current_value + curr_step, self.task_params.MAX_CURRENT)

        self.trial_in_ch += 1
        
        # Check if channel is finished
        if (self.reversal_count >= self.task_params.MAX_REVERSALS or 
            self.trial_in_ch >= self.task_params.MAX_TRIALS_PER_CH):
            self.channel_done = True

    def next_trial(self):
        if self.channel_done:
            self.current_ch_idx += 1
            if self.current_ch_idx >= len(self.channels_to_test):
                logger.info("All channels tested. Ending session.")
                self.run_status = False # Signal end of session
            else:
                logger.info(f"Switching to channel {self.channels_to_test[self.current_ch_idx]}")
                self.trial_in_ch = 0
                self.reversal_count = 0
                self.current_value = self.task_params.INIT_CURRENT
                self.last_outcome = None
                self.channel_done = False

        self.trial_num += 1
        self.draw_next_trial_info()

    def draw_next_trial_info(self):
        # We don't have much to randomize here as it's a staircase
        super().draw_next_trial_info()

if __name__ == '__main__':
    kwargs = iblrig.misc.get_task_arguments(parents=[Session.extra_parser()])
    sess = Session(**kwargs)
    sess.run()
