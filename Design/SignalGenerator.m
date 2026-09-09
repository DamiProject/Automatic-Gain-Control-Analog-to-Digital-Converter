classdef SignalGenerator < handle
    %% ==============================================
    %% FRAME-BASED TEST SIGNAL GENERATION FOR THE ADC
    %% ==============================================
    properties
        ADCParameters
    end

    properties (SetAccess = private)
        % Zero-based index of the first sample in the next frame.
        NextSampleIndex = 0

        % Number of nonempty frames generated since construction/reset.
        FramesGenerated = 0
    end

    methods
        %% =====================================
        %% Signal Generator Instance Constructor
        %% =====================================
        function obj = SignalGenerator(P)
            obj.ADCParameters = P;
            obj.Reset();
        end

        function [Inp_Sig, t, Components, FrameInfo] = ...
                GenNoisySignal(obj)
            %% ==========================================
            %% GENERATE THE NEXT COMPOSITE-SIGNAL FRAME
            %% ==========================================
            % FrameLength is Nf: the requested number of samples in one
            % frame. It is stored centrally in Parameters. The final frame
            % can contain fewer than Nf samples when Fs*Dur is not an
            % integer multiple of FrameLength.

            FrameLength = ...
                obj.ADCParameters.getValue("FrameLength");
            obj.ValidateFrameLength(FrameLength);
            FrameLength = double(FrameLength);

            Fs = obj.ADCParameters.getValue("Fs");
            TotalSamples = obj.GetTotalSamples();

            % A call made after the complete signal has been generated
            % returns correctly shaped empty outputs and does not advance
            % the frame state.
            if obj.NextSampleIndex >= TotalSamples
                [Inp_Sig, t, Components, FrameInfo] = ...
                    obj.CreateEmptyFrame(TotalSamples);
                return
            end

            %% ==========================================
            %% GLOBAL SAMPLE AND TIME AXES FOR THIS FRAME
            %% ==========================================
            FirstSampleIndex = obj.NextSampleIndex;
            LastSampleIndex = min( ...
                FirstSampleIndex + FrameLength - 1, ...
                TotalSamples - 1);

            SampleIndex = (FirstSampleIndex:LastSampleIndex)';
            t = SampleIndex / Fs;

            %% ==========================================
            %% GAUSSIAN-BURST INFORMATION ENVELOPE
            %% ==========================================
            Aburst = obj.ADCParameters.getValue("Aburst");
            mu = obj.ADCParameters.getValue("mu");
            Sigma = obj.ADCParameters.getValue("Sigma");
            Ad = obj.ADCParameters.getValue("Ad");

            BurstEnvelope = Aburst * ...
                exp(-((t - mu).^2) / (2 * Sigma^2));
            Envelope = Ad + BurstEnvelope;

            %% ==========================================
            %% GLOBAL EXPONENTIAL FADE
            %% ==========================================
            % The fade reference is calculated from the first global
            % sample at or after EST. Therefore its value is independent of
            % where a frame boundary happens to fall.
            Lambda = obj.ADCParameters.getValue("Lambda");
            EST = obj.ADCParameters.getValue("EST");

            FadeStartSampleIndex = ...
                obj.FirstSampleAtOrAfter(EST, Fs);
            FadeIndex = SampleIndex >= FadeStartSampleIndex;

            if any(FadeIndex)
                FadeStartTime = FadeStartSampleIndex / Fs;
                FadeStartValue = Ad + Aburst * exp( ...
                    -((FadeStartTime - mu)^2) / (2 * Sigma^2));

                FadeEnvelope = exp( ...
                    -Lambda * (t(FadeIndex) - EST));
                Envelope(FadeIndex) = ...
                    FadeStartValue * FadeEnvelope;
            end

            %% ==========================================
            %% FRAME SIGNAL COMPONENTS
            %% ==========================================
            FData = obj.ADCParameters.getValue("FData");
            DataSignal = sin(2 * pi * FData * t) .* Envelope;

            An = obj.ADCParameters.getValue("An");
            Fnoise = obj.ADCParameters.getValue("Fnoise");
            InterferenceSignal = An * sin(2 * pi * Fnoise * t);

            Anf = obj.ADCParameters.getValue("Anf");
            NoiseFloor = Anf * randn(size(t));

            DCValue = obj.ADCParameters.getValue("DC");
            DC = DCValue * ones(size(t));

            Inp_Sig = DC + DataSignal + InterferenceSignal + NoiseFloor;

            Components.Envelope = Envelope;
            Components.DataSignal = DataSignal;
            Components.InterferenceSignal = InterferenceSignal;
            Components.NoiseFloor = NoiseFloor;
            Components.DC = DC;

            %% ==========================================
            %% UPDATE PERSISTENT FRAME STATE
            %% ==========================================
            obj.NextSampleIndex = LastSampleIndex + 1;
            obj.FramesGenerated = obj.FramesGenerated + 1;

            FrameInfo.FrameNumber = obj.FramesGenerated;
            FrameInfo.SampleIndex = SampleIndex;
            FrameInfo.StartSampleIndex = FirstSampleIndex;
            FrameInfo.EndSampleIndex = LastSampleIndex;
            FrameInfo.NumValidSamples = numel(SampleIndex);
            FrameInfo.IsLastFrame = ...
                obj.NextSampleIndex >= TotalSamples;
            FrameInfo.TotalSamples = TotalSamples;
        end

        function [Inp_Sig, t, Components, FrameInfo] = ...
                GenNoisyTwoDataSignals(obj)
            %% ===================================================
            %% GENERATE A FRAME CONTAINING TWO DATA-SIGNAL TONES
            %% ===================================================
            % Generate the original composite-signal frame first so the
            % frame position, time axis, noise, DC offset, burst, and fade
            % remain identical to GenNoisySignal.
            [Inp_Sig, t, Components, FrameInfo] = ...
                obj.GenNoisySignal();

            % Preserve the original nonstationary data signal as the first
            % tone and generate a second tone with an independent constant
            % amplitude and frequency.
            DataSignal1 = Components.DataSignal;

            FData2 = obj.ADCParameters.getValue("FData2");
            Ad2 = obj.ADCParameters.getValue("Ad2");
            DataSignal2 = ...
                Ad2 * sin(2 * pi * FData2 * t);

            % The complete data signal is the sum of both tones. Retain the
            % individual components so their FFT peaks can be inspected
            % independently as well as in the combined waveform.
            Components.DataSignal1 = DataSignal1;
            Components.DataSignal2 = DataSignal2;
            Components.DataSignal = ...
                DataSignal1 + DataSignal2;

            Inp_Sig = Inp_Sig + DataSignal2;
        end

        function Reset(obj)
            %% ========================================
            %% RESET FRAME POSITION TO THE FIRST SAMPLE
            %% ========================================
            % Reset intentionally resets the sample/frame position only.
            % Use rng(seed) separately when an identical AWGN realization
            % is also required after a reset.
            obj.NextSampleIndex = 0;
            obj.FramesGenerated = 0;
        end

        function Complete = IsDone(obj)
            %% ==========================================
            %% REPORT WHETHER ALL VALID SAMPLES ARE EMITTED
            %% ==========================================
            Complete = ...
                obj.NextSampleIndex >= obj.GetTotalSamples();
        end
    end

    methods (Access = private)
        function TotalSamples = GetTotalSamples(obj)
            %% Convert duration to an exact discrete sample count.
            Fs = obj.ADCParameters.getValue("Fs");
            Dur = obj.ADCParameters.getValue("Dur");

            RawTotalSamples = Fs * Dur;
            TotalSamples = round(RawTotalSamples);

            IntegerTolerance = ...
                100 * eps(max(1, abs(RawTotalSamples)));

            if abs(RawTotalSamples - TotalSamples) > IntegerTolerance
                error('SignalGenerator:NonIntegerTotalSamples', ...
                    ['Fs*Dur must be an integer so the finite signal ', ...
                     'contains an exact number of samples.']);
            end

            if TotalSamples < 1
                error('SignalGenerator:NoSamples', ...
                    'Fs*Dur must describe at least one sample.');
            end
        end

        function SampleIndex = FirstSampleAtOrAfter(~, Time, Fs)
            %% Find ceil(Time*Fs), while protecting exact integer products
            %% from a one-sample floating-point roundoff error.
            ScaledTime = Time * Fs;
            NearestInteger = round(ScaledTime);
            IntegerTolerance = 100 * eps(max(1, abs(ScaledTime)));

            if abs(ScaledTime - NearestInteger) <= IntegerTolerance
                SampleIndex = NearestInteger;
            else
                SampleIndex = ceil(ScaledTime);
            end
        end

        function ValidateFrameLength(~, FrameLength)
            ValidFrameLength = ...
                isnumeric(FrameLength) && isscalar(FrameLength) && ...
                isreal(FrameLength) && isfinite(FrameLength) && ...
                FrameLength > 0 && FrameLength == floor(FrameLength);

            if ~ValidFrameLength
                error('SignalGenerator:InvalidFrameLength', ...
                    'FrameLength must be a finite positive integer scalar.');
            end
        end

        function [Inp_Sig, t, Components, FrameInfo] = ...
                CreateEmptyFrame(obj, TotalSamples)
            %% Create stable empty outputs after end-of-stream.
            EmptyColumn = zeros(0, 1);

            Inp_Sig = EmptyColumn;
            t = EmptyColumn;

            Components.Envelope = EmptyColumn;
            Components.DataSignal = EmptyColumn;
            Components.InterferenceSignal = EmptyColumn;
            Components.NoiseFloor = EmptyColumn;
            Components.DC = EmptyColumn;

            FrameInfo.FrameNumber = obj.FramesGenerated;
            FrameInfo.SampleIndex = EmptyColumn;
            FrameInfo.StartSampleIndex = NaN;
            FrameInfo.EndSampleIndex = NaN;
            FrameInfo.NumValidSamples = 0;
            FrameInfo.IsLastFrame = true;
            FrameInfo.TotalSamples = TotalSamples;
        end
    end
end
