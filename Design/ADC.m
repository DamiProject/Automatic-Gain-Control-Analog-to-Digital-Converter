classdef ADC < handle
    %% ==============================
    %% SAMPLER AND QUANTIZER SYSTEM
    %% ==============================

    properties
        ADCParameters
    end

    properties (SetAccess = private)
        %% =============================================
        %% FRAME-BASED ADC DOWNSAMPLER STREAMING STATE
        %% =============================================
        % Number of high-rate input samples consumed since reset.
        InputSamplesProcessed = 0

        % Number of ADC-rate output samples emitted since reset.
        OutputSamplesProduced = 0

        % Number of nonempty input frames processed since reset.
        FramesProcessed = 0
    end

    methods
        function obj = ADC(P)
            %% ===========================================
            %% SAMPLER AND QUANTIZER INSTANCE CONSTRUCTOR
            %% ===========================================
            obj.ADCParameters = P;
            obj.ResetSampler();
        end

        function [DiscreteSignal, SampleIndex , ADCSamplingFrequency] = ...
            Sampler(obj, InputFrame)
            %% ========================================
            %% FRAME-BASED ADC DOWNSAMPLING / SAMPLING
            %% ========================================
            % The ADC sampling phase is referenced to global input sample
            % zero. A frame boundary therefore never restarts the sequence
            % 0, DF, 2*DF, ... . SampleIndex contains those zero-based
            % global source-sample indices for the current output frame.

            ValidFrame = isnumeric(InputFrame) && ...
                isreal(InputFrame) && ...
                (isvector(InputFrame) || isempty(InputFrame)) && ...
                all(isfinite(InputFrame(:)));

            if ~ValidFrame
                error('ADC:InvalidSamplerFrame', ...
                    ['InputFrame must be a finite, real-valued ', ...
                     'numeric vector.']);
            end

            DF = obj.ADCParameters.getValue("DF");
            obj.ValidateDownsamplingFactor(DF);
            DF = double(DF);

            Fs = obj.ADCParameters.getValue("Fs");
            ADCSamplingFrequency = Fs / DF;

            % All signal-chain frames use column-vector orientation.
            Input = double(InputFrame(:));
            N = numel(Input);

            % Empty end-of-stream calls are state-neutral.
            if N == 0
                DiscreteSignal = zeros(0, 1);
                SampleIndex = zeros(0, 1);
                return
            end

            FirstGlobalSampleIndex = obj.InputSamplesProcessed;

            % Zero-based offset of the first ADC sampling instant that
            % occurs inside this frame. This can be nonzero whenever the
            % input frame length is not an integer multiple of DF.
            FirstLocalOffset = mod(-FirstGlobalSampleIndex, DF);
            LocalSampleIndex = ...
                (FirstLocalOffset + 1:DF:N)';

            DiscreteSignal = Input(LocalSampleIndex);
            SampleIndex = FirstGlobalSampleIndex + ...
                (LocalSampleIndex - 1);

            % Advance the stream position after the full input frame has
            % been accepted, including frames with no ADC output sample.
            obj.InputSamplesProcessed = ...
                FirstGlobalSampleIndex + N;
            obj.OutputSamplesProduced = ...
                obj.OutputSamplesProduced + numel(DiscreteSignal);
            obj.FramesProcessed = obj.FramesProcessed + 1;
        end

        function ResetSampler(obj)
            %% =====================================
            %% RESET ADC DOWNSAMPLER STREAMING STATE
            %% =====================================
            obj.InputSamplesProcessed = 0;
            obj.OutputSamplesProduced = 0;
            obj.FramesProcessed = 0;
        end

        function [QuantSignal, Indices, Error] = Midtread(obj,Input)

            %% ADC Midtread Uniform Bipolar Quantizer

            Vfs = obj.ADCParameters.getValue("Vfs");% full-scale range
            NumBits = obj.ADCParameters.getValue("NumBits"); % Number of Bits

            Input = Input(:); %Discrete-time input signal

            Delta = Vfs/2^NumBits; % Quantization resolution

            min_Vfs = -(Vfs/2); % Lowest Quantizer voltage level

            Indices = round((Input-min_Vfs)/Delta); % Quantization Indices
            Indices = max(0, min(Indices, (2^NumBits- 1))); % Clip Protect

            QuantSignal = min_Vfs + (Indices * Delta); % Quantized Signal

            Error = QuantSignal - Input; % Quantization error
        end
    
        function [QuantSignal, Indices, Error] = Midrise(obj,Input)

            %% ADC Midrise Uniform Bipolar Quantizer

            Vfs = obj.ADCParameters.getValue("Vfs");% full-scale range
            NumBits = obj.ADCParameters.getValue("NumBits"); % Number of Bits

            Input = Input(:); % Discrete-time input signal

            Delta = Vfs/2^NumBits; % Quantization resolution

            min_Vfs = -(Vfs/2); % Lowest Quantizer voltage level

            Indices = floor((Input-min_Vfs)/Delta); % Quantization Indices

            Indices = max(0, min(Indices, (2^NumBits) - 1)); % Clip protect

            QuantSignal = min_Vfs + ...
            ((Indices + 0.5) * Delta); % Quantized Signal

            Error = QuantSignal - Input; % Quantization error
        end
    end

    methods (Access = private, Static)
        function ValidateDownsamplingFactor(DF)
            %% Validates DF Before It Is Used as a Sampling Interval

            ValidDF = isnumeric(DF) && isscalar(DF) && ...
                isreal(DF) && isfinite(DF) && ...
                DF > 0 && DF == floor(DF);

            if ~ValidDF
                error('ADC:InvalidDownsamplingFactor', ...
                    ['DF must be a finite positive integer scalar ', ...
                     'for frame-based downsampling.']);
            end
        end
    end
end
