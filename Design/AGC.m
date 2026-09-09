classdef AGC < handle
    %% ===================================================
    %% TIME-VARYING AUTOMATIC GAIN CONTROL WITH NOISE GATE
    %% ===================================================
    properties
        ADCParameters
    end

    properties (SetAccess = private)
        Envelope = 0.0; %% Initial Value of the Envelope/Level Detector
        Gain = 1.0; %% Initial AGC Gain
        GateGain = 1.0; %% Initial Noise Gate Gain

        % Global frame-processing position and completed-frame count
        SamplesProcessed = 0;
        FramesProcessed = 0;
    end

    properties (Access = private)

        GatePeak = 1.0; %% Fully open gate target
        GateFloor = 0.0; %% Fully closed gate target

        UpperAGCLimit %% Upper output-envelope limit for AGC control
        LowerAGCLimit %% Lower output-envelope limit for AGC control

        NoiseThreshold %% Envelope threshold used to detect noise/silence
        
        % Minimum denominator for upper-limit gain calculation
        SafetyFloorHigh 
        % Minimum denominator for lower-limit gain calculation
        SafetyFloorLow

    end

    methods
        function obj = AGC(P)
            %% =========================
            %% AGC INSTANCE CONSTRUCTOR
            %% =========================
            obj.ADCParameters = P;
            obj.Gain = obj.GetConfiguredInitialGain();
        end
        
        function [OutputAGCSignal, t, History] = ...
                GainControl(obj, InputFrame)
            %% ======================================
            %% FRAME-BASED AUTOMATIC GAIN CONTROL
            %% ======================================
            % The final Envelope, Gain, and GateGain values from this call
            % are the initial values used by the next input frame.

            ValidFrame = isnumeric(InputFrame) && ...
                isreal(InputFrame) && ...
                (isvector(InputFrame) || isempty(InputFrame)) && ...
                all(isfinite(InputFrame(:)));

            if ~ValidFrame
                error('AGC:InvalidInputFrame', ...
                    ['InputFrame must be a finite, real-valued ', ...
                     'numeric vector.']);
            end

            Input = double(InputFrame(:));

            % Signal and history allocation for the current frame.
            N = numel(Input);

            %% Pre-Allocate Automatic Gain Control output
            % Signal Fed Into ADC (Sampler + Quantizer)
            OutputAGCSignal = zeros(N, 1);
            % Automatic Gain Controlled Signal Amplitude Local To AGC
            AGCSignal = zeros(N, 1);

            %% Pre-Allocate History 

            % Stores AGC Gain Value for Each Sample Of The Envelope/Level -
            %Detector
            History.Gain = zeros(N, 1);

            % Stores AGC Gain & Noise Gate Gain Value for Each Sample of - 
            % the Envelope/Level Detector
            History.EffectiveGain = zeros(N, 1);

            % Stores Each Sample Value of the Envelope/Level Detector
            History.Envelope = zeros(N, 1);

            % Stores Each Gain Adjusted Sample Value of the 
            % Envelope/Level Detector
            History.ProjectedEnvelope = zeros(N, 1);

            % Stores Automatic Gain Controlled Signal Amplitude 
            History.AGCSignal = zeros(N, 1);
            
            %Stores Noise Gate Gain Value
            History.GateGain = zeros(N, 1);

            % Stores the zero-based global sample index for this frame.
            History.SampleIndex = zeros(N, 1);

            % Empty end-of-stream frames are state-neutral and do not count
            % as processed frames.
            if N == 0
                t = zeros(0, 1);
                return
            end

            Fs = obj.ADCParameters.getValue("Fs"); % Sampling Rate

            FirstSampleIndex = obj.SamplesProcessed;
            SampleIndex = ...
                FirstSampleIndex + (0:N-1)';
            t = SampleIndex / Fs;
            History.SampleIndex = SampleIndex;
      
            %% Local Caching of AGC System Properties

            % Envelope/Level Detector
            Envelope = obj.Envelope;
            % AGC Gain
            Gain = obj.Gain;
            % Noise Gate Gain
            GateGain = obj.GateGain;
            % Open Noise Gate Target 
            GatePeak = obj.GatePeak;
            % Close Noise Gate Target
            GateFloor = obj.GateFloor;
            % Configuration-defined AGC gain bounds. Keeping these values
            % outside the AGC implementation allows each design to select
            % the gain range required by its input dynamic range and ADC
            % full-scale specification.
            MinGain = ...
                obj.ADCParameters.getValue("MinAGCGain");
            MaxGain = ...
                obj.ADCParameters.getValue("MaxAGCGain");

            if MinGain > MaxGain
                error('AGC:InvalidGainRange', ...
                    ['MinAGCGain must be less than or equal to ', ...
                     'MaxAGCGain.']);
            end

            %% Derive AGC Limits and Thresholds From Parameters

            % Use a design-specific threshold when one is configured. The
            % NaN fallback preserves the original two-times-noise-amplitude
            % behavior for existing test and legacy configurations.
            NoiseThreshold = ...
                obj.ADCParameters.getValue("NoiseGateThreshold");

            if isnan(NoiseThreshold)
                Anf = obj.ADCParameters.getValue("Anf");
                NoiseThreshold = abs(Anf) * 2;
            end

            % Quantizer full-scale Amplitude Parameter
            Vfs = obj.ADCParameters.getValue("Vfs");
            % Quantizer Peak Voltage 
            QuantizerPeak = abs(Vfs) / 2;
            % Headroom Calculation of the Upper output-envelope limit -
            % for AGC control 
            UpperAGCLimit = 0.75 * QuantizerPeak;
            % Headroom Calculation of the Lower output-envelope limit -
            % for AGC control 
            LowerAGCLimit = 0.3 * QuantizerPeak;
            
            % Minimum denominator for upper-limit gain calculation
            SafetyFloorHigh = max (eps, UpperAGCLimit *1e-6);
            % Minimum denominator for lower-limit gain calculation
            SafetyFloorLow =  max(eps, LowerAGCLimit * 1e-6);

            %% Store Derived AGC Limits and Thresholds

            %Upper output-envelope limit for AGC control 
            obj.UpperAGCLimit = UpperAGCLimit;
            %Lower output-envelope limit for AGC control 
            obj.LowerAGCLimit = LowerAGCLimit;
            % Envelope threshold used to detect noise/silence
            obj.NoiseThreshold = NoiseThreshold;
            % Minimum denominator for upper-limit gain calculation
            obj.SafetyFloorHigh = SafetyFloorHigh;
            % Minimum denominator for lower-limit gain
            obj.SafetyFloorLow = SafetyFloorLow;
            
            %% Convert Attack/Release Times Into Per-Sample Coefficients
            
            % Envelope/Level Detector Attack Time Constant
            EnvAttack = obj.ADCParameters.getValue("EnvAttack");
            % Pole of the Envelope/Level Detector Leaky Integrator -
            % Based on the Attack Time Constant
            Pev_att = exp(-1 / (EnvAttack * Fs));
            
            % Envelope/Level Detector Release Time Constant
            EnvRelease = obj.ADCParameters.getValue("EnvRelease");
            % Pole of the Envelope/Level Detector Leaky Integrator -
            % Based on the Release Time Constant
            Pev_rel =  exp(-1 / (EnvRelease * Fs));

            % AGC Gain Attack Time Constant
            GainAttack = obj.ADCParameters.getValue("GainAttack");
            % Pole of the AGC Gain Leaky Integrator Based on the Attack -
            % Time Constant
            Pgn_att =  exp(-1 / (GainAttack * Fs));
            % Smoothing Attack Factor of the AGC Gain Leaky Integrator. 
            Alpha_att = 1 - Pgn_att;

            % AGC Gain Release Time Constant
            GainRelease = obj.ADCParameters.getValue("GainRelease");
            % Pole of the AGC Gain Leaky Integrator Based on the Release -
            % Time Constant
            Pgn_rel = exp(-1 / (GainRelease * Fs));
            % Smoothing Release Factor of the AGC Gain Leaky Integrator. 
            Alpha_rel = 1 -  Pgn_rel;
            
            % Noise Gate Gain Attack Time Constant
            GateAttack = obj.ADCParameters.getValue("GateAttack");
            % Pole of the Noise Gate Gain Leaky Integrator Based -
            % on the Attack Time Constant
            Pgt_att =  exp(-1 / (GateAttack * Fs));
            % Smoothing Attack Factor of the Noise Gate Gain -
            % Leaky Integrator
            Beta_att = 1 - Pgt_att;

            % Noise Gate Gain Release Time Constant
            GateRelease = obj.ADCParameters.getValue("GateRelease"); 
            % Pole of the Noise Gate Gain Leaky Integrator Based -
            % on the Release Time Constant
            Pgt_rel = exp(-1 / (GateRelease * Fs));
            % Smoothing Release Factor of the Noise Gate Gain -
            % Leaky Integrator. 
            Beta_rel = 1 -  Pgt_rel;
            
            for k = 1:N

                %% FeedForward Envelope/Level Detection
                CurrentInputEnvelope = abs(Input(k));
                
                % Smoothing of the Envelope/Level Detection Process Using
                % A Leaky Integrator
                if   CurrentInputEnvelope > Envelope
                    Envelope = (1 - Pev_att) *  CurrentInputEnvelope + ...
                    Pev_att * Envelope;
                else
                    Envelope = (1 - Pev_rel) *  CurrentInputEnvelope + ... 
                    Pev_rel * Envelope ;
                 end
         
                % Smoothing of The Noise Gate Gain Operations Using A Leaky
                % Integrator
                if Envelope > NoiseThreshold
                    % Signal is active: Attack/Ramp the gate back to 1.0
                    GateGain = Beta_att * GatePeak + Pgt_att * GateGain;            
                else
                  % Signal is below threshold: Decay the gate  
                    GateGain = Beta_rel * GateFloor + Pgt_rel * GateGain;
                end
                
                %Acceptable Noise Gate Gain Value Range
                GateGain = obj.clamp(GateGain, GateFloor, GatePeak);
                
                % Estimated output envelope after applying the 
                % current AGC gain
                ProjectedEnvelope = Envelope * Gain;
                
                %% Smoothing of the Time-Varying AGC Gain Update Operations 
                %% Using A Leaky Integrator
                if Envelope > NoiseThreshold   

                    % Reduce gain when the projected output envelope 
                    % exceeds the upper limit
                    if ProjectedEnvelope > UpperAGCLimit

                        % Desired gain needed to bring the -
                        % output envelope to the limit
                        DesiredGain = UpperAGCLimit / ...
                        max(Envelope, SafetyFloorHigh);  

                        % Bound of the Acceptable Gain Value Per Sample
                        DesiredGain =  ...
                        obj.clamp(DesiredGain, MinGain, MaxGain);

                        %Error = DesiredGain - Gain;

                        % Smooth Gain Update Using A Leaky Integrator
                        Gain = Alpha_att * DesiredGain + Pgn_att * Gain;

                        % Increase gain when the projected output envelope
                        % is below the lower limit 
                    elseif ProjectedEnvelope < LowerAGCLimit

                        % Desired gain needed to bring the output 
                        % envelope up to the lower limit
                        DesiredGain = LowerAGCLimit / ...
                        max (Envelope, SafetyFloorLow);

                        % Bound of the Acceptable Gain Value Per Sample
                        DesiredGain = ...
                        obj.clamp(DesiredGain, MinGain, MaxGain);

                        %Error = DesiredGain - Gain;

                        % Smooth Gain Update Using A Leaky Integrator
                        Gain = Alpha_rel * DesiredGain  + Pgn_rel * Gain;
                    else 
                       % Projected envelope is within the allowed range,
                       % so keep the current AGC gain.
                    end
                else
                 % Freeze AGC gain update during noise/silence.
                 % The noise gate still attenuates the output.
                end
                % Bound Of Generated Current AGC Gain Value
                Gain = obj.clamp(Gain, MinGain, MaxGain);
                
                % Updated estimate of output envelope after the 
                % new AGC gain
                ProjectedEnvelope = Envelope * Gain;
                    
                
                %% Apply Current Gain To Create Outputs

                % Automatic Gain Controlled Signal Before Noise Gate
                AGCSignal(k) = Input(k) * Gain;

                % Final AGC Output After Applying The Noise Gate
                OutputAGCSignal(k) = AGCSignal(k) * GateGain;
             
                %% Record Historical Tracking

                % AGC Gain Value at Current Sample
                History.Gain(k) = Gain;

                % AGC Gain & Noise Gate Applied To The Input Signal
                History.EffectiveGain(k) = Gain * GateGain;

                % Envelope/Level Detector Value at Current Sample
                History.Envelope(k) = Envelope;

                % Estimated Output Envelope After AGC Gain
                History.ProjectedEnvelope(k) = ProjectedEnvelope;

                % AGC Signal Before Noise Gate 
                History.AGCSignal(k) = AGCSignal(k);   
                
                % Noise Gate Value at Current Sample
                History.GateGain(k) = GateGain;
            end
            
            %% Store final AGC Property states

            %Envelope/Level Detector
            obj.Envelope = Envelope;
            
            %AGC Gain
            obj.Gain = Gain;

            % Noise Gate Gain
            obj.GateGain = GateGain;

            % Advance the zero-based global position only after the complete
            % frame has been processed successfully.
            obj.SamplesProcessed = FirstSampleIndex + N;
            obj.FramesProcessed = obj.FramesProcessed + 1;
        end

        function reset(obj)
            %% ==========================
            %% RESET AGC INTERNAL STATE
            %% ==========================
            % Initial Value of the Envelope/Level Detector
            obj.Envelope = 0.0;
            % Restore the configuration-defined safe startup gain.
            obj.Gain = obj.GetConfiguredInitialGain();
            % Initial Noise Gate Gain
            obj.GateGain = 1.0;
            % First global sample index and completed-frame count
            obj.SamplesProcessed = 0;
            obj.FramesProcessed = 0;
        end
    end

    methods (Access = private)
        function InitialGain = GetConfiguredInitialGain(obj)
            %% =============================================
            %% VALIDATE AND RETURN CONFIGURED INITIAL GAIN
            %% =============================================

            MinGain = ...
                obj.ADCParameters.getValue("MinAGCGain");
            MaxGain = ...
                obj.ADCParameters.getValue("MaxAGCGain");
            InitialGain = ...
                obj.ADCParameters.getValue("InitialAGCGain");

            if MinGain > MaxGain
                error('AGC:InvalidGainRange', ...
                    ['MinAGCGain must be less than or equal to ', ...
                     'MaxAGCGain.']);
            end

            if InitialGain < MinGain || InitialGain > MaxGain
                error('AGC:InvalidInitialGain', ...
                    ['InitialAGCGain must lie between MinAGCGain ', ...
                     'and MaxAGCGain.']);
            end
        end
    end

    methods (Access = private, Static)
        %% ====================================
        %% ACCEPTABLE LOWER & UPPER LIMIT BOUND
        %% =====================================
        function y = clamp(x, lowerLimit, upperLimit)
            %% Saturates x between lowerLimit and upperLimit

            y = min(max(x, lowerLimit), upperLimit);
        end
    end

end
