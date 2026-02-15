All Ripple Micro front ends (FEs) must be connected to the 1:4 cable. 
Turn on the Trek. 
Go to Trellis. 
All FEs should be recognized by the system. Otherwise, ensure that each FE's green LED on the top edge is on. Restart Trellis. 

In Trellis, go to Launch Applications on left side. 
Then open Raster. 
Only check the Digital Events, SpkPreview, and Stim. Only data streams we care about related to behavior are Digital In 4 and the relevant Ripple stim channels which you will configure later in MATLAB. You may uncheck/hide the other data streams. 

Go to C:/iblrigv8/matlab and open test.m 
Ctrl + Enter to run a section 
Run each section one at a time starting with the addpaths
Specify the stim parameters and the GO and NO-GO trial times! 
Specify the Ripple stim channel corresponding to GO/NO-GO
The trial table is written to csv and is read by both scripts automatically 
Ctrl + Enter the Start Experiment section

Open up IBLRIG and pick paired_visual_ICMS
Make sure the parameters match those in MATLAB 
Then start 

If you hear a beep that means there was a misalignment! End the experiment on the Bpod side and contact Robin! 