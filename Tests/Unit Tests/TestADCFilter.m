classdef TestADCFilter < matlab.unittest.TestCase
    %% =================================
    %% UNIT TEST SUITE FOR FILTER CLASS
    %% =================================

    methods (Test)

        function testConstructorStoresParametersObject(testCase)
            %% Validates Constructor Stores Parameters Handle

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            testCase.verifySameHandle(F.ADCParameters, P);
        end

        function testDCRemovalReturnsValidSOS(testCase)
            %% Validates HPF Returns a Valid SOS Matrix and Scalar Gain

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            nHpf = P.getValue("nHpf");
            [sos, g] = F.DCRemoval();

            testCase.verifyValidSOS(sos, g, nHpf);
        end

        function testAAFReturnsValidSOS(testCase)
            %% Validates LPF Returns a Valid SOS Matrix and Scalar Gain

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            nLpf = P.getValue("nLpf");
            [sos, g] = F.AAF();

            testCase.verifyValidSOS(sos, g, nLpf);
        end

        function testDCRemovalMatchesExpectedHighPassButterworth(testCase)
            %% Validates DCRemoval Designs the Expected Butterworth HPF

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            FcHigh = P.getValue("FcHigh"); % Cutoff Frequency
            Fs     = P.getValue("Fs");     % Sampling Frequency
            nHpf   = P.getValue("nHpf");   % Filter Order

            [sosActual, gActual] = F.DCRemoval();

            [zExpected, pExpected, kExpected] = ...
                butter(nHpf, (2 * FcHigh) / Fs, "high");
            [sosExpected, gExpected] = ...
                zp2sos(zExpected, pExpected, kExpected);

            testCase.verifyEqual( ...
                sosActual, sosExpected, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                gActual, gExpected, "AbsTol", 1e-12);
        end

        function testAAFMatchesExpectedLowPassButterworth(testCase)
            %% Validates AAF Designs the Expected Butterworth LPF

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            FcLow = P.getValue("FcLow"); % Cutoff Frequency
            Fs    = P.getValue("Fs");    % Sampling Frequency
            nLpf  = P.getValue("nLpf");  % Filter Order

            [sosActual, gActual] = F.AAF();

            [zExpected, pExpected, kExpected] = ...
                butter(nLpf, (2 * FcLow) / Fs, "low");
            [sosExpected, gExpected] = ...
                zp2sos(zExpected, pExpected, kExpected);

            testCase.verifyEqual( ...
                sosActual, sosExpected, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                gActual, gExpected, "AbsTol", 1e-12);
        end

        function testDCRemovalBehavesAsHighPass(testCase)
            %% Validates HPF Rejects DC and Passes High Frequency

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            [sos, g] = F.DCRemoval();

            % Evaluate the complete SOS cascade, including overall gain,
            % at DC and the Nyquist frequency.
            H = g .* freqz(sos, [0, pi]);

            Hdc   = H(1);
            Hhigh = H(2);

            testCase.verifyLessThan(abs(Hdc), 1e-6);
            testCase.verifyGreaterThan(abs(Hhigh), 0.7);
        end

        function testAAFBehavesAsLowPass(testCase)
            %% Validates AAF Passes DC and Rejects High Frequency

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            [sos, g] = F.AAF();

            % Evaluate the complete SOS cascade, including overall gain,
            % at DC and the Nyquist frequency.
            H = g .* freqz(sos, [0, pi]);

            Hdc   = H(1);
            Hhigh = H(2);

            testCase.verifyGreaterThan(abs(Hdc), 0.7);
            testCase.verifyLessThan(abs(Hhigh), 1e-3);
        end

        function testDCRemovalHasButterworthCutoffResponse(testCase)
            %% Validates HPF Magnitude Is Approximately -3 dB at Cutoff

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            FcHigh = P.getValue("FcHigh");
            Fs     = P.getValue("Fs");

            [sos, g] = F.DCRemoval();

            cutoffFrequency = 2 * pi * FcHigh / Fs;
            Hcutoff = g .* freqz(sos, [cutoffFrequency, pi]);

            testCase.verifyEqual( ...
                abs(Hcutoff(1)), 1 / sqrt(2), "AbsTol", 1e-6);
        end

        function testAAFHasButterworthCutoffResponse(testCase)
            %% Validates LPF Magnitude Is Approximately -3 dB at Cutoff

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            FcLow = P.getValue("FcLow");
            Fs    = P.getValue("Fs");

            [sos, g] = F.AAF();

            cutoffFrequency = 2 * pi * FcLow / Fs;
            Hcutoff = g .* freqz(sos, [cutoffFrequency, pi]);

            testCase.verifyEqual( ...
                abs(Hcutoff(1)), 1 / sqrt(2), "AbsTol", 1e-6);
        end

        function testDCRemovalFilterIsStable(testCase)
            %% Validates All HPF Poles Are Inside the Unit Circle

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            [sos, g] = F.DCRemoval();
            [~, poles, ~] = sos2zp(sos, g);

            testCase.verifyLessThan(abs(poles), ones(size(poles)));
        end

        function testAAFFilterIsStable(testCase)
            %% Validates All LPF Poles Are Inside the Unit Circle

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            [sos, g] = F.AAF();
            [~, poles, ~] = sos2zp(sos, g);

            testCase.verifyLessThan(abs(poles), ones(size(poles)));
        end

        function testHPFFrameReturnsColumnWithMatchingLength(testCase)
            %% Validates Frame Shape and Lazy HPF State Initialization

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            InputFrame = ones(1, 16);
            OutputFrame = F.ProcessHPFFrame(InputFrame);

            ExpectedSections = ceil(P.getValue("nHpf") / 2);

            testCase.verifySize(OutputFrame, [16, 1]);
            testCase.verifyTrue(iscolumn(OutputFrame));
            testCase.verifyTrue(F.HPFInitialized);
            testCase.verifySize( ...
                F.HPFState, [2, ExpectedSections]);
            testCase.verifySize( ...
                F.HPFSOS, [ExpectedSections, 6]);
        end

        function testHPFFramesMatchWholeVectorReference(testCase)
            %% Validates Frame Boundaries Do Not Reset the IIR Response

            P = testCase.createDefaultParameters();
            Fs = P.getValue("Fs");

            SampleIndex = (0:102)';
            InputSignal = 0.75 + ...
                0.25 * sin(2 * pi * 300 * SampleIndex / Fs) + ...
                0.10 * cos(2 * pi * 4000 * SampleIndex / Fs);

            ReferenceFilter = ADCFilter(P);
            [sos, g] = ReferenceFilter.DCRemoval();
            ExpectedOutput = sosfilt(sos, g * InputSignal);

            FrameFilter = ADCFilter(P);
            FrameLengths = [17, 11, 31, 44];
            ActualOutput = zeros(0, 1);
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputSignal(StartIndex:EndIndex);

                OutputFrame = ...
                    FrameFilter.ProcessHPFFrame(InputFrame);
                ActualOutput = ...
                    [ActualOutput; OutputFrame]; %#ok<AGROW>

                StartIndex = EndIndex + 1;
            end

            testCase.verifyEqual( ...
                ActualOutput, ExpectedOutput, "AbsTol", 1e-12);
        end

        function testHPFStatePersistsBetweenFrames(testCase)
            %% Validates Every Biquad Carries Its State Into the Next Frame

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            F.ProcessHPFFrame(ones(12, 1));
            StateAfterFirstFrame = F.HPFState;

            F.ProcessHPFFrame(zeros(9, 1));
            StateAfterSecondFrame = F.HPFState;

            testCase.verifyNotEqual( ...
                StateAfterFirstFrame, zeros(size(StateAfterFirstFrame)));
            testCase.verifyNotEqual( ...
                StateAfterSecondFrame, StateAfterFirstFrame);
        end

        function testResetHPFReproducesFirstFrameResponse(testCase)
            %% Validates ResetHPF Clears All Stored Biquad Delays

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            SampleIndex = (0:19)';
            InputFrame = 0.5 + sin( ...
                2 * pi * 1000 * SampleIndex / P.getValue("Fs"));

            FirstOutput = F.ProcessHPFFrame(InputFrame);
            F.ProcessHPFFrame(0.25 * ones(13, 1));

            F.ResetHPF();

            testCase.verifyEqual( ...
                F.HPFState, zeros(size(F.HPFState)));

            ResetOutput = F.ProcessHPFFrame(InputFrame);

            testCase.verifyEqual( ...
                ResetOutput, FirstOutput, "AbsTol", 1e-12);
        end

        function testEmptyHPFFrameDoesNotChangeState(testCase)
            %% Validates Empty End-of-Stream Frames Are State-Neutral

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            EmptyOutputBeforeInitialization = ...
                F.ProcessHPFFrame(zeros(0, 1));

            testCase.verifySize( ...
                EmptyOutputBeforeInitialization, [0, 1]);
            testCase.verifyFalse(F.HPFInitialized);

            F.ProcessHPFFrame(ones(8, 1));
            StateBeforeEmptyFrame = F.HPFState;

            EmptyOutput = F.ProcessHPFFrame(zeros(0, 1));

            testCase.verifySize(EmptyOutput, [0, 1]);
            testCase.verifyEqual(F.HPFState, StateBeforeEmptyFrame);
        end

        function testHPFRejectsInvalidFrameInput(testCase)
            %% Validates HPF Frame Input Must Be a Finite Real Vector

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            InvalidFrames = { ...
                ones(2, 2), ...
                [1; NaN], ...
                [1; Inf], ...
                [1; 1i] ...
                };

            for k = 1:numel(InvalidFrames)
                InvalidFrame = InvalidFrames{k};

                testCase.verifyError( ...
                    @() F.ProcessHPFFrame(InvalidFrame), ...
                    'ADCFilter:InvalidHPFFrame');
            end

            testCase.verifyFalse(F.HPFInitialized);
        end

        function testLPFFrameReturnsColumnWithMatchingLength(testCase)
            %% Validates Frame Shape and Lazy LPF State Initialization

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            InputFrame = ones(1, 16);
            OutputFrame = F.ProcessLPFFrame(InputFrame);

            ExpectedSections = ceil(P.getValue("nLpf") / 2);

            testCase.verifySize(OutputFrame, [16, 1]);
            testCase.verifyTrue(iscolumn(OutputFrame));
            testCase.verifyTrue(F.LPFInitialized);
            testCase.verifySize( ...
                F.LPFState, [2, ExpectedSections]);
            testCase.verifySize( ...
                F.LPFSOS, [ExpectedSections, 6]);
        end

        function testLPFFramesMatchWholeVectorReference(testCase)
            %% Validates Frame Boundaries Do Not Reset the LPF Response

            P = testCase.createDefaultParameters();
            Fs = P.getValue("Fs");

            SampleIndex = (0:112)';
            InputSignal = 0.40 + ...
                0.50 * sin(2 * pi * 1000 * SampleIndex / Fs) + ...
                0.20 * cos(2 * pi * 8000 * SampleIndex / Fs);

            ReferenceFilter = ADCFilter(P);
            [sos, g] = ReferenceFilter.AAF();
            ExpectedOutput = sosfilt(sos, g * InputSignal);

            FrameFilter = ADCFilter(P);
            FrameLengths = [19, 7, 33, 54];
            ActualOutput = zeros(0, 1);
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputSignal(StartIndex:EndIndex);

                OutputFrame = ...
                    FrameFilter.ProcessLPFFrame(InputFrame);
                ActualOutput = ...
                    [ActualOutput; OutputFrame]; %#ok<AGROW>

                StartIndex = EndIndex + 1;
            end

            testCase.verifyEqual( ...
                ActualOutput, ExpectedOutput, "AbsTol", 1e-12);
        end

        function testLPFStatePersistsBetweenFrames(testCase)
            %% Validates Every LPF Biquad Carries State Into the Next Frame

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            F.ProcessLPFFrame(ones(12, 1));
            StateAfterFirstFrame = F.LPFState;

            F.ProcessLPFFrame(zeros(9, 1));
            StateAfterSecondFrame = F.LPFState;

            testCase.verifyNotEqual( ...
                StateAfterFirstFrame, zeros(size(StateAfterFirstFrame)));
            testCase.verifyNotEqual( ...
                StateAfterSecondFrame, StateAfterFirstFrame);
        end

        function testResetLPFReproducesFirstFrameResponse(testCase)
            %% Validates ResetLPF Clears All Stored LPF Biquad Delays

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            SampleIndex = (0:19)';
            InputFrame = 0.5 + sin( ...
                2 * pi * 1000 * SampleIndex / P.getValue("Fs"));

            FirstOutput = F.ProcessLPFFrame(InputFrame);
            F.ProcessLPFFrame(0.25 * ones(13, 1));

            F.ResetLPF();

            testCase.verifyEqual( ...
                F.LPFState, zeros(size(F.LPFState)));

            ResetOutput = F.ProcessLPFFrame(InputFrame);

            testCase.verifyEqual( ...
                ResetOutput, FirstOutput, "AbsTol", 1e-12);
        end

        function testEmptyLPFFrameDoesNotChangeState(testCase)
            %% Validates Empty End-of-Stream Frames Are State-Neutral

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            EmptyOutputBeforeInitialization = ...
                F.ProcessLPFFrame(zeros(0, 1));

            testCase.verifySize( ...
                EmptyOutputBeforeInitialization, [0, 1]);
            testCase.verifyFalse(F.LPFInitialized);

            F.ProcessLPFFrame(ones(8, 1));
            StateBeforeEmptyFrame = F.LPFState;

            EmptyOutput = F.ProcessLPFFrame(zeros(0, 1));

            testCase.verifySize(EmptyOutput, [0, 1]);
            testCase.verifyEqual(F.LPFState, StateBeforeEmptyFrame);
        end

        function testLPFRejectsInvalidFrameInput(testCase)
            %% Validates LPF Frame Input Must Be a Finite Real Vector

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            InvalidFrames = { ...
                ones(2, 2), ...
                [1; NaN], ...
                [1; Inf], ...
                [1; 1i] ...
                };

            for k = 1:numel(InvalidFrames)
                InvalidFrame = InvalidFrames{k};

                testCase.verifyError( ...
                    @() F.ProcessLPFFrame(InvalidFrame), ...
                    'ADCFilter:InvalidLPFFrame');
            end

            testCase.verifyFalse(F.LPFInitialized);
        end

        function testHPFAndLPFStatesResetIndependently(testCase)
            %% Validates Resetting LPF Does Not Disturb HPF State

            P = testCase.createDefaultParameters();
            F = ADCFilter(P);

            InputFrame = 0.5 + sin(2 * pi * (0:23)' / 8);
            HPFOutputFrame = F.ProcessHPFFrame(InputFrame);
            F.ProcessLPFFrame(HPFOutputFrame);

            HPFStateBeforeLPFReset = F.HPFState;

            F.ResetLPF();

            testCase.verifyEqual( ...
                F.HPFState, HPFStateBeforeLPFReset);
            testCase.verifyEqual( ...
                F.LPFState, zeros(size(F.LPFState)));
            testCase.verifyTrue(F.HPFInitialized);
            testCase.verifyTrue(F.LPFInitialized);
        end

        function testImpulseTailCrossesHPFAndLPFFrameBoundary(testCase)
            %% Validates an IIR impulse tail is never truncated by a frame

            P = testCase.createDefaultParameters();
            N = 192;
            BoundarySample = 32;

            InputSignal = zeros(N, 1);
            InputSignal(BoundarySample) = 1;

            % One-frame reference also supplies the expected terminal states.
            WholeFilter = ADCFilter(P);
            ExpectedHPFOutput = ...
                WholeFilter.ProcessHPFFrame(InputSignal);
            ExpectedLPFOutput = ...
                WholeFilter.ProcessLPFFrame(ExpectedHPFOutput);

            % Place the impulse at the final sample of the first frame. The
            % recursive tail must continue into every following frame.
            FrameFilter = ADCFilter(P);
            FrameLengths = [32, 7, 53, 100];
            ActualHPFOutput = zeros(0, 1);
            ActualLPFOutput = zeros(0, 1);
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputSignal(StartIndex:EndIndex);

                HPFOutputFrame = ...
                    FrameFilter.ProcessHPFFrame(InputFrame);
                LPFOutputFrame = ...
                    FrameFilter.ProcessLPFFrame(HPFOutputFrame);

                ActualHPFOutput = ...
                    [ActualHPFOutput; HPFOutputFrame]; %#ok<AGROW>
                ActualLPFOutput = ...
                    [ActualLPFOutput; LPFOutputFrame]; %#ok<AGROW>

                StartIndex = EndIndex + 1;
            end

            testCase.verifyEqual( ...
                ActualHPFOutput, ExpectedHPFOutput, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualLPFOutput, ExpectedLPFOutput, "AbsTol", 1e-12);

            testCase.verifyGreaterThan( ...
                norm(ActualLPFOutput(BoundarySample + 1:end), inf), ...
                1e-12);

            testCase.verifyEqual( ...
                FrameFilter.HPFState, WholeFilter.HPFState, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                FrameFilter.LPFState, WholeFilter.LPFState, ...
                "AbsTol", 1e-12);
        end

       
    end

    methods (Access = private)

        function verifyValidSOS(testCase, sos, g, filterOrder)
            %% Validates the Structure and Numeric Integrity of SOS Outputs

            expectedSections = ceil(filterOrder / 2);

            testCase.verifySize(sos, [expectedSections, 6]);
            testCase.verifyEqual( ...
                sos(:, 4), ones(expectedSections, 1), ...
                "AbsTol", 1e-12);

            testCase.verifyNotEmpty(sos);
            testCase.verifyTrue(isreal(sos));
            testCase.verifyTrue(all(isfinite(sos(:))));

            testCase.verifySize(g, [1, 1]);
            testCase.verifyTrue(isnumeric(g));
            testCase.verifyTrue(isreal(g));
            testCase.verifyTrue(isfinite(g));
        end

        function P = createDefaultParameters(~)
            %% Creates Default Parameter Object for Filter Tests

            P = ADCParameters();

            P.setValue("Fs", 20000);     % Sampling Frequency
            P.setValue("FcHigh", 20);    % HPF Cutoff Frequency
            P.setValue("FcLow", 5000);   % LPF Cutoff Frequency
            P.setValue("nHpf", 4);       % HPF Filter Order
            P.setValue("nLpf", 6);       % LPF Filter Order
        end
    end
end
