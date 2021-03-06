classdef LEDSineWithScanTrigger < edu.washington.riekelab.turner.protocols.LaserScanProtocol

    % LED modulated sinusoidally, with 2P scan trigger
    
    properties
        led                             % Output LED
        preTime = 500                    % Sine leading duration (ms)
        stimTime = 3000                  % Sine duration (ms)
        tailTime = 500                   % Sine trailing duration (ms)
        sineMean = 0.5                   % Sine amplitude (V)
        sineAmplitude = 0.5              % Sine amplitude (V)
        sineFrequency = 4               % Sine frequency (Hz)
        numberOfAverages = uint16(5)    % Number of epochs
        interpulseInterval = 0          % Duration between ramps (s)
        amp                             % Input amplifier
    end
    
    
    properties (Hidden)
        ledType
        ampType
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()obj.createLedStimulus());
        end
        
        function obj = prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp));
            
            device = obj.rig.getDevice(obj.led);
            device.background = symphonyui.core.Measurement(obj.sineMean, device.background.displayUnits);
        end
        
        function stim = createLedStimulus(obj)
            period = 1000 / obj.sineFrequency; %msec
            
            gen = symphonyui.builtin.stimuli.SineGenerator();
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.amplitude = obj.sineAmplitude;
            gen.period = period;
            gen.mean = obj.sineMean;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.led).background.displayUnits;
            stim = gen.generate();
        end
    
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.turner.protocols.LaserScanProtocol(obj, epoch);

            epoch.addStimulus(obj.rig.getDevice(obj.led), obj.createLedStimulus());
            epoch.addResponse(obj.rig.getDevice(obj.amp));
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.led);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
                

    end
    
end

