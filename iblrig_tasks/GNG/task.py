from typing import Tuple, Any
import logging
from pydantic import BaseModel, NonNegativeInt, NonNegativeFloat
from iblrig.base_choice_world import ChoiceWorldSession
import iblrig.misc
from iblrig.pydantic_definitions import TrialDataModel
import numpy as np
from iblutil.util import setup_logger


log = logging.getLogger('iblrig.task')

class StimGNGTrialData(TrialDataModel):
    trial_num: NonNegativeInt 
    reward_amount: NonNegativeFloat 
    reward_valve_time: NonNegativeFloat
    stim_current: NonNegativeInt 
    is_catch_trial: bool 


class StimGNGSession(ChoiceWorldSession):
    """
    The StimGNGSession is a base class for protocols where the wheel is oriented forwards-backwards
    so any wheel displacement past an angular threshold is considered a "hit". 
    The purpose of this protocol is to evaluate the efficacy of microstimulation using a go/no-go task. 
    It has the following characteristics:

    - it is trial based
    - forwards or backwards is considered a hit 
    - only stimulus is microstimulation 
    """
    TrialDataModel = StimGNGTrialData

    def __init__(self, *args, response_period_s=2, iti_s=2, reward_amount_ul=3, **kwargs):
        super().__init__(*args, **kwargs)
        self.task_params['RESPONSE_PERIOD_S'] = response_period_s
        self.task_params['ITI_S'] = iti_s
        self.task_params.REWARD_AMOUNT_UL = reward_amount_ul

    @staticmethod
    def extra_parser():
        """:return: argparse.parser()"""
        parser = super(ChoiceWorldSession, ChoiceWorldSession).extra_parser()
        parser.add_argument(
            '--response_period_s',
            dest='response_period_s',
            default=2,
            type=float,
            required=False,
            help='Response period in seconds',
        )
        parser.add_argument(
            '--iti_s',
            dest='iti_s',
            default=2,
            type=float,
            required=False,
            help='Intertrial interval in seconds',
        )
        parser.add_argument(
            '--reward_amount_ul',
            dest='reward_amount_ul',
            default=3,
            type=float,
            required=False,
            help='Reward amount in uL',
        )
        return parser
        

    def show_trial_log(self, log_level: int = logging.INFO):
        trial_info = self.trials_table.iloc[self.trial_num]
        info_dict = {
            'Trial number': trial_info.trial_num,
            'Time from Start': self.time_elapsed,
            'Water delivered': f'{self.session_info.TOTAL_WATER_DELIVERED:.1f} ul',
            'Current': f'{trial_info.stim_current} uA'
        }
        log.log(log_level, f'Outcome of Trial #{trial_info.trial_num}:')
        max_key_length = max(len(key) for key in info_dict)
        for key, value in info_dict.items():
            spaces = (max_key_length - len(key)) * ' '
            log.log(log_level, f'- {key}: {spaces}{str(value)}')

    def trial_completed(self, bpod_data):
        # trial reward is either default reward amount or 0 
        self.TrialDataModel.is_catch_trial = False 
        trial_reward = self.default_reward_amount if not self.TrialDataModel.is_catch_trial else 0.0
        # TODO can't read from table since empty..need to specify trial 0 params prior to running trial 0? 
        # if self.trials_table.at[self.trial_num, 'is_catch_trial']:
        #     trial_reward = 0.0
        # else:
        #     # trial_reward = self.default_reward_amount if bpod_data...
        is_hit_trial = ~np.isnan(bpod_data['States timestamps']['reward'][0][0])
        trial_reward = self.default_reward_amount if is_hit_trial else 0.0
        self.session_info.TOTAL_WATER_DELIVERED += trial_reward
        self.session_info.NTRIALS += 1

        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'reward_valve_time'] = self.reward_time
        self.trials_table.at[self.trial_num, 'reward_amount'] = trial_reward
        self.trials_table.at[self.trial_num, 'stim_current'] = 0
        self.trials_table.at[self.trial_num, 'is_catch_trial'] = self.TrialDataModel.is_catch_trial

    def draw_next_trial_info(self, **kwargs):
        """Draw next trial variables.
        This is called by the `next_trial` method before updating the Bpod state machine.
        """   
        self.TrialDataModel.is_catch_trial = False 
        trial_reward = self.default_reward_amount if not self.TrialDataModel.is_catch_trial else 0.0

        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'is_catch_trial'] = self.TrialDataModel.is_catch_trial
        self.trials_table.at[self.trial_num, 'reward_amount'] = trial_reward
        self.trials_table.at[self.trial_num, 'stim_current'] = 0
        self.trials_table.at[self.trial_num, 'reward_valve_time'] = 0.5

        for key, value in kwargs.items():
            if key == 'index':
                pass
            self.trials_table.at[self.trial_num, key] = value

    def start_hardware(self):
        self.start_mixin_bpod()
        self.start_mixin_valve()
        self.start_mixin_rotary_encoder()

    # override parent method 
    def get_state_machine_trial(self, i):
        sma = self._instantiate_state_machine(trial_number=i)
        sma.set_global_timer_legacy(timer_id=1, timer_duration=self.task_params.RESPONSE_PERIOD_S)

        if i == 0:  
            session_delay_start = self.task_params.get('SESSION_DELAY_START', 0)
            sma.add_state(
                state_name='delay_initiation',
                state_timer=session_delay_start,
                output_actions=[self.bpod.actions.rotary_encoder_reset],
                state_change_conditions={'Tup': 'trial_start'},
            )

        sma.add_state(
            state_name='trial_start',
            state_timer=0,  # ~100µs hardware irreducible delay
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
            output_actions=[], #("BNC1", 1)
            state_change_conditions={
                self.movement_left: "reward",
                self.movement_right: "reward",
                "GlobalTimer1_End": "miss_ITI"
            }
        ) 

        sma.add_state(
            state_name="reward",
            state_timer = self.reward_time,
            output_actions=[
                ("Valve1", 255),
                self.bpod.actions.rotary_encoder_reset,
                #("BNC1", 1)
            ],
            state_change_conditions={
                "Tup": "hit_ITI",
                "GlobalTimer1_End": "hit_ITI"
            }
        )

        for ITI_state_name in ["miss_ITI", "hit_ITI"]:
            sma.add_state(
                state_name=ITI_state_name,
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



class Session(StimGNGSession): 
    protocol_name = '_iblrig_tasks_stimGNG'
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
    
if __name__ == '__main__':  # pragma: no cover
    kwargs = iblrig.misc.get_task_arguments(parents=[Session.extra_parser()])
    sess = Session(**kwargs)
    sess.run()