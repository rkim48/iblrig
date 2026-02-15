import logging
from pathlib import Path
import numpy as np 
from typing import Optional, Literal
from pydantic import NonNegativeFloat, NonNegativeInt

from iblrig.base_choice_world import ChoiceWorldSession
import iblrig.misc
from iblrig.pydantic_definitions import TrialDataModel

logger = logging.getLogger('iblrig.task')
logger.setLevel(logging.INFO)

class Stage0TrialData(TrialDataModel):

    trial_num: NonNegativeInt
    reward_amount: NonNegativeFloat
    turn_direction: Optional[Literal["forwards", "backwards"]] = None
    response_time: Optional[float] = np.nan

class Session(ChoiceWorldSession):
    
    TrialDataModel = Stage0TrialData
    protocol_name = 'stage0'

    def __init__(self, *args, response_period_s=2, iti_s=0.5, reward_amount_ul=3.0, wheel_gain=8.0, **kwargs):
        super().__init__(*args, **kwargs)
        self.task_params['RESPONSE_PERIOD_S'] = response_period_s
        self.task_params['ITI_S'] = iti_s
        self.task_params['REWARD_AMOUNT_UL'] = reward_amount_ul
        self.task_params['WHEEL_GAIN'] = wheel_gain

    @staticmethod
    def extra_parser():
        parser = super(Session, Session).extra_parser()
        parser.add_argument(
            '--response_period_s',
            option_strings=['--response_period_s'],
            dest='response_period_s',
            default=2,
            type=float,
            help='trial time (s)',
        )
        parser.add_argument(
            '--iti_s',
            option_strings=['--iti_s'],
            dest='iti_s',
            default=0.5,
            type=float,
            help='intertrial interval (s)',
        )
        parser.add_argument(
            '--reward_amount_ul',
            option_strings=['--reward_amount_ul'],
            dest='reward_amount_ul',
            default=3.0,
            type=float,
            help='reward volume in microliters',
        )
        parser.add_argument(
            '--wheel_gain',
            option_strings=['--wheel_gain'],
            dest='wheel_gain',
            default=8.0,
            type=float,
            help='wheel gain (deg/mm)',
        )
        return parser
    
    def start_hardware(self):
        self.start_mixin_bpod()
        self.start_mixin_valve()
        self.start_mixin_rotary_encoder()

    
    def save_trials_table_to_csv(self):
        """
        Save the trials_table DataFrame to disk as a CSV.
        """
        save_path = self.paths.SESSION_RAW_DATA_FOLDER.joinpath('_iblrig_trialTable.csv')
        self.trials_table.to_csv(save_path, index=False)

    def show_trial_log(self, log_level: int = logging.INFO):
        trial_info = self.trials_table.iloc[self.trial_num]
        info_dict = {
            'Trial number': trial_info.trial_num,
            'Time from Start': self.time_elapsed,
            'Water delivered': f'{self.session_info.TOTAL_WATER_DELIVERED:.1f} ul',
            'Turn direction': f'{trial_info.turn_direction}' if not np.isnan(trial_info.response_time) else 'No response',
            'Response time': f'{trial_info.response_time} s\n' if not np.isnan(trial_info.response_time) else 'No response\n',
        }
        logger.log(log_level, f'Outcome of Trial #{trial_info.trial_num}:')
        max_key_length = max(len(key) for key in info_dict)
        for key, value in info_dict.items():
            spaces = (max_key_length - len(key)) * ' '
            logger.log(log_level, f'- {key}: {spaces}{str(value)}')

    def trial_completed(self, bpod_data):
        event_timestamps = bpod_data['States timestamps']
        is_forward = ~np.isnan(event_timestamps['forward_reward'][0][0])
        is_backward = ~np.isnan(event_timestamps['backward_reward'][0][0])
        is_hit_trial = is_forward or is_backward
        
        trial_reward = self.default_reward_amount if is_hit_trial else 0.0
        if is_forward:
            turn_direction = "forwards"
        elif is_backward:
            turn_direction = "backwards"
        else:
            turn_direction = None  
        
        reward_ts = event_timestamps['forward_reward'][0][0] if is_forward else (
            event_timestamps['backward_reward'][0][0] if is_backward else np.nan
        )
        response_time = reward_ts - event_timestamps['response_period'][0][0] if is_hit_trial else np.nan

        self.session_info.TOTAL_WATER_DELIVERED += trial_reward
        self.session_info.NTRIALS += 1 

        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'reward_amount'] = trial_reward
        self.trials_table.at[self.trial_num, 'turn_direction'] = turn_direction
        self.trials_table.at[self.trial_num, 'response_time'] = np.round(response_time, 3)   
        self.save_trial_data_to_json(bpod_data)
        self.save_trials_table_to_csv()

    def draw_next_trial_info(self, **kwargs):
        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'reward_amount'] = self.default_reward_amount

        for key, value in kwargs.items():
            if key == 'index':
                pass
            self.trials_table.at[self.trial_num, key] = value

    def get_state_machine_trial(self, i):
        sma = self._instantiate_state_machine(trial_number=i)
        sma.set_global_timer_legacy(timer_id=1, timer_duration=self.task_params.RESPONSE_PERIOD_S)

        if i == 0:  
            sma.add_state(
                state_name='delay_initiation',
                state_timer=1,
                output_actions=[self.bpod.actions.rotary_encoder_reset],
                state_change_conditions={'Tup': 'trial_start'},
            )

        sma.add_state(
            state_name='trial_start',
            state_timer=0,  
            output_actions=[(self.bpod.OutputChannels.GlobalTimerTrig, 1)],
            state_change_conditions={'Tup': 'reset_rotary_encoder'},
        )  

        sma.add_state(
            state_name='reset_rotary_encoder',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={
                "Tup": "response_period",
            }
        )

        sma.add_state(  
            state_name="response_period",
            state_timer=0,
            output_actions=[], 
            state_change_conditions={
                self.movement_left: "forward_reward",
                self.movement_right: "backward_reward",
                "GlobalTimer1_End": "ITI"
            }
        ) 

        for reward_state_name in ["forward_reward", "backward_reward"]:
            sma.add_state(
                state_name=reward_state_name,
                state_timer = self.reward_time,
                output_actions=[
                    ("Valve1", 255),
                    self.bpod.actions.rotary_encoder_reset,
                ],
                state_change_conditions={
                    "Tup": "ITI",
                    "GlobalTimer1_End": "ITI"
                }
            )

        sma.add_state(
            state_name="ITI",
            state_timer = self.task_params.ITI_S,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={
                "Tup": "exit_state",
            }
        )

        sma.add_state(
            state_name="exit_state",
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={"Tup": "exit"}
        )

        return sma

    def next_trial(self):
        self.trial_num += 1
        self.draw_next_trial_info()

if __name__ == '__main__':  # pragma: no cover
    kwargs = iblrig.misc.get_task_arguments(parents=[Session.extra_parser()])
    sess = Session(**kwargs)
    sess.run()