import logging
import time

import PySpin

log = logging.getLogger(__name__)


class Cameras:
    _instance = None

    def __init__(self, init_cameras: bool = True):
        self._instance = PySpin.System.GetInstance()
        self._cameras = self._instance.GetCameras()
        self._init_cameras = init_cameras
        if init_cameras:
            for camera in self._cameras:
                camera.Init()

    def __enter__(self) -> PySpin.CameraList:
        return self._cameras

    def __exit__(self, *_):
        if self._init_cameras:
            for camera in self._cameras:
                camera.DeInit()
            del camera
        self._cameras.Clear()
        self._instance.ReleaseInstance()

    @property
    def instance(self):
        return self._instance


def reset_all_cameras():
    with Cameras(init_cameras=False) as cameras:
        if len(cameras) == 0:
            return

        # Iterate through each camera and reset
        for camera in cameras:
            camera.Init()
            try:
                camera.DeviceReset()
            except PySpin.SpinnakerException as e:
                log.error(f'Error resetting camera #{camera.DeviceID()}: {e}')
            else:
                log.info(f'Resetting camera #{camera.DeviceID.ToString()} ...')
            finally:
                camera.DeInit()

        # Wait for all cameras to come back online
        log.info(f'Waiting for {"camera" if len(cameras) == 1 else "cameras"} to come back online (~10 s) ...')
        all_cameras_online = False
        while not all_cameras_online:
            all_cameras_online = True
            for camera in cameras:
                try:
                    camera.Init()
                except PySpin.SpinnakerException:
                    all_cameras_online = False
                else:
                    log.info(f'Camera #{camera.DeviceID()} is back online.')
                    camera.DeInit()
            if not all_cameras_online:
                time.sleep(0.2)
        del camera


def enable_camera_trigger(enable: bool, camera: PySpin.CameraPtr | None = None):
    if camera is None:
        with Cameras() as cameras:
            for cam in cameras:
                enable_camera_trigger(enable=enable, camera=cam)
                del cam
    else:
        node_map = camera.GetNodeMap()
        node_trigger_mode = PySpin.CEnumerationPtr(node_map.GetNode('TriggerMode'))
        node_trigger_mode_value = node_trigger_mode.GetEntryByName('On' if enable else 'Off').GetValue()
        node_trigger_mode.SetIntValue(node_trigger_mode_value)
        log.debug(('Enabled' if enable else 'Disabled') + f' trigger for camera #{camera.DeviceID()}.')
