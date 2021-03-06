classdef LinearEquivalentDiscMixedSurround < edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol

    properties
        preTime = 200 % ms
        stimTime = 200 % ms
        tailTime = 200 % ms

        apertureDiameter = 250 % um
        linearIntegrationFunction = 'gaussian'
        rfSigmaCenter = 50 % (um) Enter from fit RF
        
        annulusInnerDiameter = 250; %  um
        annulusOuterDiameter = 600; % um

        numberOfAverages = uint16(360) % 6 * noPatches * noAvg
    end
    
    properties (Hidden)
        linearIntegrationFunctionType = symphonyui.core.PropertyType('char', 'row', {'gaussian','uniform'})       
        
        allEquivalentIntensityValues
        
        mixedSurroundPatchLocations
        mixedSurroundPatchMatrix
        
        %saved out to each epoch...
        imagePatchIndex
        currentCenterLocation
        equivalentIntensity
        stimulusTag %image, equiv
        surroundTag %none, nat, mix
        currentMixedSurroundPatchLocation
        
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'stimulusTag'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            if ~strcmp(obj.onlineAnalysis,'none')
                responseDimensions = [2, 3, obj.noPatches]; %image/equiv by surround condition by image patch
                obj.showFigure('edu.washington.riekelab.turner.figures.ModImageVsIntensityFigure',...
                obj.rig.getDevice(obj.amp),responseDimensions,...
                'recordingType',obj.onlineAnalysis,...
                'stimType','NaturalImageMixedSurround',...
                'preTime',obj.preTime,'stimTime',obj.stimTime);
            end

            %get center equivalent intensities:
            obj.allEquivalentIntensityValues = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getEquivalentIntensityValues(...
                obj, 0, obj.apertureDiameter, obj.rfSigmaCenter);
            
            %get mixed surround locations:
            resourcesDir = 'C:\Users\Public\Documents\turner-package\resources\';
            rng(obj.seed + 1); %set random seed different than center
            load([resourcesDir,obj.currentStimSet,'.mat']);
            fieldName = ['imk', obj.imageName];
            xLoc = imageData.(fieldName).location(:,1);
            yLoc = imageData.(fieldName).location(:,2);
            pullInds = randsample(1:length(xLoc),obj.noPatches);
            obj.mixedSurroundPatchLocations(1,1:obj.noPatches) = xLoc(pullInds); %in VH pixels
            obj.mixedSurroundPatchLocations(2,1:obj.noPatches) = yLoc(pullInds);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            %pull current image:
            epochsPerImagePatch = 6; %image and equiv for each of 3 surround conditions
            obj.imagePatchIndex = floor(mod(obj.numEpochsCompleted/epochsPerImagePatch,obj.noPatches) + 1);
            
            %center patch location:
            obj.currentCenterLocation(1) = obj.patchLocations(1,obj.imagePatchIndex); %in VH pixels
            obj.currentCenterLocation(2) = obj.patchLocations(2,obj.imagePatchIndex);
            obj.equivalentIntensity = obj.allEquivalentIntensityValues(obj.imagePatchIndex);
            %center patch matrix:
            obj.imagePatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentCenterLocation);
            
            %mixed surround patch location:
            obj.currentMixedSurroundPatchLocation(1) = obj.mixedSurroundPatchLocations(1,obj.imagePatchIndex); %in VH pixels
            obj.currentMixedSurroundPatchLocation(2) = obj.mixedSurroundPatchLocations(2,obj.imagePatchIndex);
            %mixed surround patch matrix:
            obj.mixedSurroundPatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentMixedSurroundPatchLocation);
            
            %which center stim?
            evenInd = mod(obj.numEpochsCompleted,2);
            if evenInd == 1 %even, show uniform linear equivalent intensity
                obj.stimulusTag = 'intensity';
            elseif evenInd == 0 %odd, show image
                obj.stimulusTag = 'image';
            end
            %which surround stim?
            surInd = mod(floor(obj.numEpochsCompleted./2),3);
            if surInd == 0 %no surround
                obj.surroundTag = 'none';
            elseif surInd == 1 %natural, matched surround
                obj.surroundTag = 'nat';
            elseif surInd == 2 %mixed surround
                obj.surroundTag = 'mixed';
            end

            epoch.addParameter('imagePatchIndex', obj.imagePatchIndex);
            epoch.addParameter('currentCenterLocation', obj.currentCenterLocation);
            epoch.addParameter('equivalentIntensity', obj.equivalentIntensity);
            epoch.addParameter('stimulusTag', obj.stimulusTag);
            epoch.addParameter('surroundTag', obj.surroundTag);
            epoch.addParameter('currentMixedSurroundPatchLocation', obj.currentMixedSurroundPatchLocation);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);

            % Add surround
            if strcmp(obj.surroundTag,'none')
                %no surround
            else %image in surround
                if strcmp(obj.surroundTag,'nat')
                    scene = stage.builtin.stimuli.Image(obj.imagePatchMatrix);
                elseif strcmp(obj.surroundTag,'mixed')
                    scene = stage.builtin.stimuli.Image(obj.mixedSurroundPatchMatrix);
                end
                scene.size = canvasSize; %scale up to canvas size
                scene.position = canvasSize/2;
                % Use linear interpolation when scaling the image.
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);

                % Add mask to make image appear only in annulus
                distanceMatrix = createDistanceMatrix(canvasSize(1),canvasSize(2));
                annulus = uint8((distanceMatrix < annulusOuterDiameterPix/2 & ...
                    distanceMatrix >= annulusInnerDiameterPix/2) * 255);
                surroundMask = stage.core.Mask(annulus);
                scene.setMask(surroundMask);
                
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            end

            %add center image
            if strcmp(obj.stimulusTag,'image') %image in center
                scene = stage.builtin.stimuli.Image(obj.imagePatchMatrix);
                scene.size = canvasSize; %scale up to canvas size
                scene.position = canvasSize/2;
                % Use linear interpolation when scaling the image.
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);
                
                % Add mask to make image appear only in center
                distanceMatrix = createDistanceMatrix(canvasSize(1),canvasSize(2));
                annulus = uint8((distanceMatrix < apertureDiameterPix/2) * 255);
                centerMask = stage.core.Mask(annulus);
                scene.setMask(centerMask);
                
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            elseif strcmp(obj.stimulusTag,'intensity') %uniform disc in center
                disc = stage.builtin.stimuli.Ellipse();
                disc.radiusX = apertureDiameterPix/2;
                disc.radiusY = apertureDiameterPix/2;
                disc.color = obj.equivalentIntensity;
                disc.position = canvasSize/2;
                p.addStimulus(disc);
                sceneVisible = stage.builtin.controllers.PropertyController(disc, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            end

            function m = createDistanceMatrix(sizeX,sizeY)
                [xx, yy] = meshgrid(1:sizeX,1:sizeY);
                m = sqrt((xx-(sizeX/2)).^2+(yy-(sizeY/2)).^2);
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end

    end
    
end