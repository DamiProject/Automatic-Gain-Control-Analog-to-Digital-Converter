classdef TestGeneratorADCFilter < matlab.unittest.TestCase
    %% ======================================
    %% INTEGRATED TEST SUITE FOR FILTER CLASS
    %% ======================================

    methods (Test)
        function testSignalGeneratorToHPFFrameIntegration(testCase)
            %% Validates the First Frame-Based Signal-Chain Boundary

            P = testCase.createSignalGeneratorFilterParameters();
            SG = SignalGenerator(P);
            F = ADCFilter(P);

            CompleteInput = zeros(0, 1);
            CompleteOutput = zeros(0, 1);

            while ~SG.IsDone()
                [InputFrame, ~, ~, FrameInfo] = ...
                    SG.GenNoisySignal();
                OutputFrame = F.ProcessHPFFrame(InputFrame);

                testCase.verifySize( ...
                    OutputFrame, [FrameInfo.NumValidSamples, 1]);

                CompleteInput = ...
                    [CompleteInput; InputFrame]; %#ok<AGROW>
                CompleteOutput = ...
                    [CompleteOutput; OutputFrame]; %#ok<AGROW>
            end

            [sos, g] = F.DCRemoval();
            ExpectedOutput = sosfilt(sos, g * CompleteInput);

            testCase.verifyEqual( ...
                CompleteOutput, ExpectedOutput, "AbsTol", 1e-12);
            testCase.verifyEqual(numel(CompleteInput), 100);
            testCase.verifyTrue(SG.IsDone());
        end

        function testSignalGeneratorToHPFToLPFFrameIntegration(testCase)
            %% Validates Signal Generator -> HPF -> LPF Frame Processing

            P = testCase.createSignalGeneratorFilterParameters();
            SG = SignalGenerator(P);
            F = ADCFilter(P);

            CompleteInput = zeros(0, 1);
            CompleteHPFOutput = zeros(0, 1);
            CompleteLPFOutput = zeros(0, 1);

            while ~SG.IsDone()
                [InputFrame, ~, ~, FrameInfo] = ...
                    SG.GenNoisySignal();
                HPFOutputFrame = ...
                    F.ProcessHPFFrame(InputFrame);
                LPFOutputFrame = ...
                    F.ProcessLPFFrame(HPFOutputFrame);

                testCase.verifySize( ...
                    HPFOutputFrame, [FrameInfo.NumValidSamples, 1]);
                testCase.verifySize( ...
                    LPFOutputFrame, [FrameInfo.NumValidSamples, 1]);

                CompleteInput = ...
                    [CompleteInput; InputFrame]; %#ok<AGROW>
                CompleteHPFOutput = ...
                    [CompleteHPFOutput; HPFOutputFrame]; %#ok<AGROW>
                CompleteLPFOutput = ...
                    [CompleteLPFOutput; LPFOutputFrame]; %#ok<AGROW>
            end

            [sosHPF, gHPF] = F.DCRemoval();
            [sosLPF, gLPF] = F.AAF();

            ExpectedHPFOutput = ...
                sosfilt(sosHPF, gHPF * CompleteInput);
            ExpectedLPFOutput = ...
                sosfilt(sosLPF, gLPF * ExpectedHPFOutput);

            testCase.verifyEqual( ...
                CompleteHPFOutput, ...
                ExpectedHPFOutput, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                CompleteLPFOutput, ...
                ExpectedLPFOutput, "AbsTol", 1e-12);
            testCase.verifyEqual(numel(CompleteLPFOutput), 100);
            testCase.verifyTrue(SG.IsDone());
            testCase.verifyTrue(F.HPFInitialized);
            testCase.verifyTrue(F.LPFInitialized);
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

        function P = createSignalGeneratorFilterParameters(testCase)
            %% Creates Parameters for Signal Generator -> HPF Integration

            P = testCase.createDefaultParameters();

            P.setValue("FrameLength", 32); % Nf, samples per frame
            P.setValue("Dur", 0.005);      % 100 total samples
            P.setValue("Aburst", 0.5);
            P.setValue("mu", 0.0015);
            P.setValue("Sigma", 0.0005);
            P.setValue("Ad", 1.0);
            P.setValue("Lambda", 300);
            P.setValue("EST", 0.003);
            P.setValue("FData", 500);
            P.setValue("An", 0.1);
            P.setValue("Fnoise", 7000);
            P.setValue("Anf", 0);
            P.setValue("DC", 0.25);
        end
    end
end