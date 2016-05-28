classdef SinePlusImage < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        preTime = 250 % ms
        stimTime = 3000 % ms
        tailTime = 250 % ms
        contrast = 0.75 % relative to mean (0-1)
        temporalFrequency = 2 % Hz
        spotDiameter = 200; % um
        
        stepFrames = 3 % (display frames) length of each image flash
        annulusInnerDiameter = 250 % um
        annulusOuterDiameter = 600 % um
        imageName = '00152' %van hateren image names
        seed = 1 % rand seed for picking image patches
        noPatches = 20 %number of different image patches to show

        centerOffset = [0, 0] % [x,y] (um)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(180) % number of epochs to queue
        amp % Output amplifier
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        centerOffsetType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        imageNameType = symphonyui.core.PropertyType('char', 'row', {'00152','00377','00405','00459','00657','01151','01154',...
            '01192','01769','01829','02265','02281','02733','02999','03093',...
            '03347','03447','03584','03758','03760'})
        
        wholeImageMatrix
        imagePatchMatrix
        patchLocations
        phases
        
        %saved out to each epoch...
        currentStimSet
        backgroundIntensity
        imagePatchIndex
        currentPhase
        currentPatchLocation
    end
       
    properties (Hidden, Transient)
        analysisFigure
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            colors = [0,0,0 ; pmkmp(8,'CubicYF')];
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'currentPhase'},...
                'sweepColor',colors);
            obj.showFigure('edu.washington.riekelab.turner.figures.CycleAverageFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'temporalFrequency', obj.temporalFrequency,...
                'preTime', obj.preTime,'stimTime', obj.stimTime,...
                'groupBy',{'currentPhase'},...
                'sweepColor',colors);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));

            %load appropriate image...
            resourcesDir = 'C:\Users\Max Turner\Documents\GitHub\turner-package\resources\';
            obj.currentStimSet = '/VHsubsample_20160105';
            fileId=fopen([resourcesDir, obj.currentStimSet, '/imk', obj.imageName,'.iml'],'rb','ieee-be');
            img = fread(fileId, [1536,1024], 'uint16');
           
            img = double(img);
            img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
            obj.backgroundIntensity = mean(img(:));%set the mean to the mean over the image
            img = img.*255; %rescale s.t. brightest point is maximum monitor level
            obj.wholeImageMatrix = uint8(img);
            rng(obj.seed); %set random seed for fixation draw
            
            %size of the stimulus on the prep:
            stimSize = obj.rig.getDevice('Stage').getCanvasSize() .* ...
                obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'); %um
            stimSize_VHpix = stimSize ./ (3.3); %um / (um/pixel) -> pixel
            radX = round(stimSize_VHpix(1) / 2); %boundaries for fixation draws depend on stimulus size
            radY = round(stimSize_VHpix(2) / 2);
            %get patch locations:
            obj.patchLocations(1,1:obj.noPatches) = randsample((radX + 1):(1536 - radX),obj.noPatches); %in VH pixels
            obj.patchLocations(2,1:obj.noPatches) = randsample((radY + 1):(1024 - radY),obj.noPatches);
            
            %start with no image flash, just sinusoid
            %phase 100 never happens in createPresentation fxn
            obj.phases = [100, 0:pi/4:7*pi/4];
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            %determine phase to use
            ind = mod(obj.numEpochsCompleted, length(obj.phases)) + 1;
            obj.currentPhase = obj.phases(ind);
            %determine image patch to use
            if (obj.currentPhase == 100) %get new image patch
                if obj.numEpochsCompleted == 0
                    obj.imagePatchIndex = 1;
                else
                    newIndex = obj.imagePatchIndex + 1;
                    if newIndex > obj.noPatches
                        newIndex = 1; %cycled through, start again
                    end
                    obj.imagePatchIndex = newIndex;
                end
                %get the image patch:
                obj.currentPatchLocation(1) = obj.patchLocations(1,obj.imagePatchIndex); %in VH pixels
                obj.currentPatchLocation(2) = obj.patchLocations(2,obj.imagePatchIndex);
                %imagePatchMatrix is in VH pixels
                %size of the stimulus on the prep:
                stimSize = obj.rig.getDevice('Stage').getCanvasSize() .* ...
                    obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'); %um
                stimSize_VHpix = stimSize ./ (3.3); %um / (um/pixel) -> pixel
                radX = stimSize_VHpix(1) / 2; %boundaries for fixation draws depend on stimulus size
                radY = stimSize_VHpix(2) / 2;
                obj.imagePatchMatrix = obj.wholeImageMatrix(round(obj.currentPatchLocation(1)-radX):round(obj.currentPatchLocation(1)+radX),...
                    round(obj.currentPatchLocation(2)-radY):round(obj.currentPatchLocation(2)+radY));
                obj.imagePatchMatrix = obj.imagePatchMatrix';
                
            else
                %use last image patch
            end
% %             figure(30); clf;
% %             imagesc(obj.imagePatchMatrix); colormap(gray); axis image; axis equal;
            
            epoch.addParameter('currentPhase', obj.currentPhase);
            epoch.addParameter('currentStimSet', obj.currentStimSet);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('imagePatchIndex', obj.imagePatchIndex);
            epoch.addParameter('currentPatchLocation', obj.currentPatchLocation);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            %convert from microns to pixels...
            spotDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.spotDiameter);
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create image stimulus
            scene = stage.builtin.stimuli.Image(obj.imagePatchMatrix);
            scene.size = canvasSize; %scale up to canvas size
            scene.position = canvasSize/2 + centerOffsetPix;
            % Use linear interpolation when scaling the image.
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            p.addStimulus(scene);
            
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible',...
                    @(state)getSceneVisible(obj, state.frame, state.time));

            function V = getSceneVisible(obj, frame, time)
                if (time >= obj.preTime * 1e-3 && time < (obj.preTime + obj.stimTime) * 1e-3)
                    cycleFrames = 60 / obj.temporalFrequency;
                    preFrames = 60*(obj.preTime * 1e-3);
                    currentFrameInCycle = mod(frame - preFrames,cycleFrames);
                    startFrame = round((obj.currentPhase / (2*pi)) * cycleFrames);
                    targetFrames = startFrame:(startFrame+obj.stepFrames-1);
                    if ismember(currentFrameInCycle,targetFrames)
                        V = 1;
                    else
                        V = 0;
                    end
                else %not in stim points
                    V = 0;
                end
            end
            p.addController(sceneVisible);
            
            % Create aperture stimulus (outer edge of annulus)
            aperture = stage.builtin.stimuli.Rectangle();
            aperture.position = canvasSize/2 + centerOffsetPix;
            aperture.color = obj.backgroundIntensity;
            aperture.size = [max(canvasSize) max(canvasSize)];
            mask = stage.core.Mask.createCircularAperture(annulusOuterDiameterPix/max(canvasSize), 1024); %circular aperture
            aperture.setMask(mask);
            p.addStimulus(aperture);
            % Create aperture stimulus (inner edge of annulus)
            mask = stage.builtin.stimuli.Ellipse();
            mask.position = canvasSize/2 + centerOffsetPix;
            mask.color = obj.backgroundIntensity;
            mask.radiusX = annulusInnerDiameterPix/2;
            mask.radiusY = annulusInnerDiameterPix/2;
            p.addStimulus(mask);
            
            % Create modulated spot stimulus.            
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = spotDiameterPix/2;
            spot.radiusY = spotDiameterPix/2;
            spot.position = canvasSize/2 + centerOffsetPix;
            p.addStimulus(spot);
            %make it contrast-reversing
            if (obj.temporalFrequency > 0) 
                spotColor = stage.builtin.controllers.PropertyController(spot, 'color',...
                    @(state)getSpotColor(obj, state.time - obj.preTime/1e3));
                p.addController(spotColor); %add the controller
            end
            function I = getSpotColor(obj, time)
                c = obj.contrast.*sin(2 * pi * obj.temporalFrequency * time);
                I = obj.backgroundIntensity + c*obj.backgroundIntensity;
            end
            %hide during pre & post
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);

        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
    
end