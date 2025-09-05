from typing import Any
import logging
from iblrig.base_choice_world import ChoiceWorldSession
import iblrig.misc
import numpy as np
from iblrig import misc
import math
import random
from typing import Annotated, Any
from annotated_types import Interval
from pydantic import NonNegativeFloat, NonNegativeInt
from iblrig.pydantic_definitions import TrialDataModel
from iblrig.base_tasks import BonsaiVisualStimulusMixin
from iblrig.tools import call_bonsai
import time
from typing import Optional, Literal, List
from pythonosc import udp_client


logger = logging.getLogger('iblrig.task')
log_level = logging.DEBUG

class Stage1TrialData(TrialDataModel):

    trial_num: NonNegativeInt
    reward_amount: NonNegativeFloat
    turn_direction: Optional[Literal["forwards", "backwards"]] = None
    response_time: Optional[float] = np.nan
    pre_stim_period_lengths: List[float]

    contrast: Annotated[float, Interval(ge=0.0, le=1.0)]
    stim_angle: Annotated[float, Interval(ge=-180.0, le=180.0)]
    stim_freq: NonNegativeFloat
    stim_gain: float
    stim_phase: Annotated[float, Interval(ge=0.0, le=2 * math.pi)]

class CustomOSCClient(udp_client.SimpleUDPClient):
    """
    Handles communication to Bonsai using a UDP Client
    OSC channels:
        USED:
        /t  -> (int)    trial number current
        /h  -> (float)  phase of gabor for current trial
        /c  -> (float)  contrast of stimulus for current trial
        /f  -> (float)  frequency of gabor patch for current trial
        /a  -> (float)  angle of gabor patch for current trial
        /g  -> (float)  gain of RE to visual stim displacement
        /e  -> (int)    events transitions  USED BY SOFTCODE HANDLER FUNC
    """

    OSC_PROTOCOL = {
        'trial_num': dict(mess='/t', type=int),
        'stim_phase': dict(mess='/h', type=float),
        'contrast': dict(mess='/c', type=float),
        'stim_freq': dict(mess='/f', type=float),
        'stim_angle': dict(mess='/a', type=float),
        'stim_gain': dict(mess='/g', type=float),
    }

    def __init__(self, port, ip='127.0.0.1'):
        super().__init__(ip, port)

    def __del__(self):
        self._sock.close()

    def send2bonsai(self, **kwargs):
        for k, v in kwargs.items():
            if k in self.OSC_PROTOCOL:
                # need to convert basic numpy types to low-level python types for OSC module
                value = v.item() if isinstance(v, np.generic) else v
                self.send_message(self.OSC_PROTOCOL[k]['mess'], self.OSC_PROTOCOL[k]['type'](value))

    def exit(self):
        self.send_message('/x', 1)

class CustomVisualStimulusMixin(BonsaiVisualStimulusMixin):
    def init_mixin_bonsai_visual_stimulus(self, *args, **kwargs):
        # camera 7111, microphone 7112
        self.bonsai_visual_udp_client = CustomOSCClient(port=7110)

    def send_trial_info_to_bonsai(self):
        """
        Send the trial information to Bonsai via UDP.

        The OSC protocol is documented in iblrig.base_tasks.BonsaiVisualStimulusMixin
        """
        bonsai_dict = {
            k: self.trials_table[k][self.trial_num]
            for k in self.bonsai_visual_udp_client.OSC_PROTOCOL
            if k in self.trials_table.columns
        }
        logger.info(bonsai_dict)
        self.bonsai_visual_udp_client.send2bonsai(**bonsai_dict)

    def choice_world_visual_stimulus(self):
        if self.task_params.VISUAL_STIMULUS is None:
            return

        # Override with your custom workflow path
        workflow_file = self.paths.VISUAL_STIM_FOLDER.joinpath('Test', 'Test2.bonsai')
        logger.info('Stim.DisplayIndex: %s', self.hardware_settings.device_screen['DISPLAY_IDX'])
        parameters = {
            'Stim.DisplayIndex': self.hardware_settings.device_screen['DISPLAY_IDX'],
            'Stim.FileNameSyncSquareUpdate': self.paths.SESSION_RAW_DATA_FOLDER.joinpath('_iblrig_syncSquareUpdate.raw.csv'),
            'Stim.FileNamePositions': self.paths.SESSION_RAW_DATA_FOLDER.joinpath('_iblrig_encoderPositions.raw.ssv'),
            'Stim.FileNameEvents': self.paths.SESSION_RAW_DATA_FOLDER.joinpath('_iblrig_encoderEvents.raw.ssv'),
            'Stim.FileNameTrialInfo': self.paths.SESSION_RAW_DATA_FOLDER.joinpath('_iblrig_encoderTrialInfo.raw.ssv'),
            'Stim.REPortName': self.hardware_settings.device_rotary_encoder['COM_ROTARY_ENCODER'],
            'Stim.sync_x': self.task_params.SYNC_SQUARE_X,
            'Stim.sync_y': self.task_params.SYNC_SQUARE_Y,
            'Stim.TranslationZ': -self.task_params.STIM_TRANSLATION_Z,  # Keep MINUS!!
        }

        call_bonsai(workflow_file, parameters, wait=False, editor=self.task_params.BONSAI_EDITOR, bootstrap=False)
        logger.info('Giving Bonsai some extra time to start ...')
        time.sleep(2)
        logger.info('Custom Bonsai visual stimulus module loaded: OK')

class Session(CustomVisualStimulusMixin, ChoiceWorldSession):

    TrialDataModel = Stage1TrialData
    protocol_name = 'stage1'

    def __init__(self, *args, go_stim_time_s=30, stim_angle=0, reward_amount_ul=3.0, psp_offset_time_s=0.2, **kwargs):
        super().__init__(*args, **kwargs)
        self.task_params.BONSAI_EDITOR = True
        self.task_params['GO_STIM_TRIAL_S'] = go_stim_time_s
        self.task_params['STIM_ANGLE'] = stim_angle
        self.task_params['REWARD_AMOUNT_UL'] = reward_amount_ul
        self.task_params['QUIESCENT_PERIOD'] = psp_offset_time_s

    @staticmethod
    def extra_parser():
        """:return: argparse.parser()"""
        parser = super(ChoiceWorldSession, ChoiceWorldSession).extra_parser()
        parser.add_argument(
            '--reward_amount_ul',
            option_strings=['--reward_amount_ul'],
            dest='reward_amount_ul',
            default=3.0,
            type=float,
            help='reward volume in microliters',
        )
        parser.add_argument(
            '--go_stim_time_s',
            dest='go_stim_time_s',
            default=30,
            type=float,
            required=False,
            metavar='Go Stim Time (s)',
            help='Go stim trial time (default: 5s)',
        )
        parser.add_argument(
            '--psp_offset_time_s',
            dest='psp_offset_time_s',
            default=0.2,
            type=float,
            required=False,
            metavar='PSP Offset Time (s)',
            help='PSP = PSP offset time + x where x ranges from 0.2 to 0.5 (default: 0.2s)',
        )
        parser.add_argument(
            '--stim_angle',
            dest='stim_angle',
            default=0,
            type=int,
            required=False,
            metavar='Stim Angle',
            help='Stim angle (default: 0 degrees)',
        )
        return parser

    def start_mixin_bonsai_visual_stimulus(self):
        self.choice_world_visual_stimulus()

    def start_hardware(self):
        self.start_mixin_bpod()
        self.start_mixin_valve()
        self.start_mixin_rotary_encoder()
        self.start_mixin_bonsai_visual_stimulus()
        self.start_mixin_sound()
        self.bpod.register_softcodes(self.softcode_dictionary())

    def get_state_machine_trial(self, i):
        sma = self._instantiate_state_machine(trial_number=i)

        if i == 0:  # First trial exception start camera
            session_delay_start = self.task_params.get('SESSION_DELAY_START', 0)
            sma.add_state(
                state_name='trial_start',
                state_timer=session_delay_start,  # ~100µs hardware irreducible delay
                state_change_conditions={'Tup': 'reset_rotary_encoder'},
                output_actions=[('BNC1', 255)],
            ) 

        sma.add_state(
            state_name='reset_rotary_encoder_1',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'quiescent_period_1'},
        )

        sma.add_state(
            state_name='quiescent_period_1',
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
            output_actions=[self.bpod.actions.rotary_encoder_reset, self.bpod.actions.play_noise],
            state_change_conditions={'Tup': 'quiescent_period'},
        )

        sma.add_state(
            state_name='quiescent_period',
            state_timer=self.quiescent_period,
            output_actions=[],
            state_change_conditions={
                'Tup': 'stim_on',
                self.movement_left: 'reset_rotary_encoder',
                self.movement_right: 'reset_rotary_encoder',
            },
        )

        sma.add_state(
            state_name='reset_rotary_encoder',
            state_timer=0,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'quiescent_period'},
        )
        

        # sma.add_state(
        #     state_name='reset_rotary_encoder_violation',
        #     state_timer=0.001,
        #     output_actions=[self.bpod.actions.rotary_encoder_reset, self.bpod.actions.play_noise],
        #     state_change_conditions={'Tup': 'quiescent_period'},
        # )

        
        sma.add_state(
            state_name='stim_on',
            state_timer=0.1,
            output_actions=[self.bpod.actions.bonsai_show_stim],
            state_change_conditions={'Tup': 'interactive_delay'},
        )

        sma.add_state(
            state_name='interactive_delay',
            state_timer=self.task_params.INTERACTIVE_DELAY,
            output_actions=[],
            state_change_conditions={'Tup': 'play_tone'},
        )

        sma.add_state(
            state_name='play_tone',
            state_timer=0.1,
            output_actions=[],
            state_change_conditions={'Tup': 'reset2_rotary_encoder', 'BNC2High': 'reset2_rotary_encoder'},
        )

        sma.add_state(
            state_name='reset2_rotary_encoder',
            state_timer=0.05,
            output_actions=[self.bpod.actions.rotary_encoder_reset],
            state_change_conditions={'Tup': 'closed_loop'},
        )

        sma.add_state(
            state_name='closed_loop',
            state_timer=self.task_params.GO_STIM_TRIAL_S,
            output_actions=[self.bpod.actions.bonsai_closed_loop],
            state_change_conditions={'Tup': 'no_go', self.event_reward_left: 'forward_freeze_reward', self.event_reward_right: 'backward_freeze_reward'},
        )
       
        sma.add_state(
            state_name='no_go',
            state_timer=self.feedback_nogo_delay,
            output_actions=[self.bpod.actions.bonsai_hide_stim],
            state_change_conditions={'Tup': 'exit_state'},
        )

        for reward_state_name in ['forward_freeze_reward', 'backward_freeze_reward']:
            sma.add_state(
                state_name=reward_state_name,
                state_timer=0,
                output_actions=[self.bpod.actions.bonsai_show_center],
                state_change_conditions={'Tup': 'reward'},
            )

        sma.add_state(
            state_name='reward',
            state_timer=self.reward_time,
            output_actions=[('Valve1', 255), ('BNC1', 255)],
            state_change_conditions={'Tup': 'correct'},
        )

        sma.add_state(
            state_name='correct',
            state_timer=self.feedback_correct_delay - self.reward_time,
            output_actions=[],
            state_change_conditions={'Tup': 'hide_stim'},
        )

        sma.add_state(
            state_name='hide_stim',
            state_timer=0.1,
            output_actions=[self.bpod.actions.bonsai_hide_stim],
            state_change_conditions={'Tup': 'exit_state', 'BNC1High': 'exit_state', 'BNC1Low': 'exit_state'},
        )

        sma.add_state(
            state_name='exit_state',
            state_timer=self.task_params.ITI_DELAY_SECS,
            output_actions=[('BNC1', 255)],
            state_change_conditions={'Tup': 'exit'},
        )

        return sma
    
    def next_trial(self):
        self.trial_num += 1
        self.draw_next_trial_info()

    def save_trials_table_to_csv(self):
        """
        Save the trials_table DataFrame to disk as a CSV.
        """
        save_path = self.paths.SESSION_RAW_DATA_FOLDER.joinpath('_iblrig_trialTable.csv')
        desired_columns = [
            'trial_num',
            'reward_amount',
            'turn_direction',
            'response_time',
            'stim_angle',
            'stim_phase',
            'pre_stim_period_value',
            'pre_stim_period_lengths'
        ]

        # Only include the desired columns that exist in the table
        columns_to_save = [col for col in desired_columns if col in self.trials_table.columns]
        
        self.trials_table[columns_to_save].to_csv(save_path, index=False)

    def trial_completed(self, bpod_data: dict[str, Any]) -> None:
        event_timestamps = bpod_data['States timestamps']
        logger.info(event_timestamps)
        is_forward = ~np.isnan(event_timestamps['forward_freeze_reward'][0][0])
        is_backward = ~np.isnan(event_timestamps['backward_freeze_reward'][0][0])
        is_hit_trial = is_forward or is_backward
        
        trial_reward = self.default_reward_amount if is_hit_trial else 0.0
        if is_forward:
            turn_direction = "forwards"
        elif is_backward:
            turn_direction = "backwards"
        else:
            turn_direction = None  
  
        response_time = event_timestamps['reward'][0][0] - event_timestamps['closed_loop'][0][0]

        pre_stim_period_lengths = [event_timestamps['quiescent_period'][i][1] - event_timestamps['quiescent_period'][i][0] for i in range(len(event_timestamps['quiescent_period']))]

        self.session_info.TOTAL_WATER_DELIVERED += trial_reward
        self.session_info.NTRIALS += 1 

        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num
        self.trials_table.at[self.trial_num, 'reward_amount'] = trial_reward
        self.trials_table.at[self.trial_num, 'turn_direction'] = turn_direction
        self.trials_table.at[self.trial_num, 'response_time'] = np.round(response_time, 3)   
        self.trials_table.at[self.trial_num, 'pre_stim_period_value'] = self.quiescent_period
        self.trials_table.at[self.trial_num, 'pre_stim_period_lengths'] = pre_stim_period_lengths

        self.save_trial_data_to_json(bpod_data)
        self.save_trials_table_to_csv()


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

    def draw_next_trial_info(self, pleft=0.5, **kwargs):
        """Draw next trial variables.

        calls :meth:`send_trial_info_to_bonsai`.
        This is called by the `next_trial` method before updating the Bpod state machine.
        """
        assert len(self.task_params.STIM_POSITIONS) == 2, 'Only two positions are supported'
        contrast = 1
        self.stim_angle = self.task_params.STIM_ANGLE
        quiescent_period = self.task_params.QUIESCENT_PERIOD + misc.truncated_exponential(
            scale=0.35, min_value=0.2, max_value=0.5
        )
        self.trials_table.at[self.trial_num, 'quiescent_period'] = quiescent_period
        self.trials_table.at[self.trial_num, 'reward_amount'] = self.default_reward_amount
        self.trials_table.at[self.trial_num, 'contrast'] = contrast
        self.trials_table.at[self.trial_num, 'stim_phase'] = random.uniform(0, 2 * math.pi)
        self.trials_table.at[self.trial_num, 'stim_angle'] = self.stim_angle
        self.trials_table.at[self.trial_num, 'stim_gain'] = self.stimulus_gain
        self.trials_table.at[self.trial_num, 'stim_freq'] = self.task_params.STIM_FREQ
        self.trials_table.at[self.trial_num, 'trial_num'] = self.trial_num

        # use the kwargs dict to override computed values
        for key, value in kwargs.items():
            if key == 'index':
                pass
            self.trials_table.at[self.trial_num, key] = value

        self.send_trial_info_to_bonsai()

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


    @property
    def event_reward_left(self):
        return self.device_rotary_encoder.THRESHOLD_EVENTS[-35]
    
    @property
    def event_reward_right(self):
        return self.device_rotary_encoder.THRESHOLD_EVENTS[35]
    

if __name__ == '__main__':  # pragma: no cover
    kwargs = iblrig.misc.get_task_arguments(parents=[Session.extra_parser()])
    sess = Session(**kwargs)
    sess.run()