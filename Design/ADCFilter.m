classdef ADCFilter < handle
    %% ====================================================
    %% PERFORMS HPF, ANTI-ALIASING/LPF FILTERING OPERATIONS
    %% ====================================================

    properties
        ADCParameters
    end

    properties (SetAccess = private)
        %% ==========================================
        %% FRAME-BASED HPF COEFFICIENTS AND IIR STATE
        %% ==========================================
        HPFSOS = zeros(0, 6)
        HPFGain = 1
        HPFState = zeros(2, 0)
        HPFInitialized = false

        %% ==========================================
        %% FRAME-BASED LPF COEFFICIENTS AND IIR STATE
        %% ==========================================
        LPFSOS = zeros(0, 6)
        LPFGain = 1
        LPFState = zeros(2, 0)
        LPFInitialized = false
    end

    methods
        function obj = ADCFilter(P)
            %% HPF OR LPF INSTANCE CONSTRUCTOR
            obj.ADCParameters = P;
        end

        function [sos_hpf, g_hpf] = DCRemoval(obj)

            %% Performs DC offset Removal using High-Pass Filter.
            FcHigh = obj.ADCParameters.getValue("FcHigh"); %Cutoff Frequency
            Fs = obj.ADCParameters.getValue("Fs");% Sampling Rate
            nHpf = obj.ADCParameters.getValue("nHpf"); % Filter Order
             
            % Butterworth filter design in Zero-Pole-Gain (ZPK) form.
            [z_hp, p_hp, k_hp] = butter(nHpf, (2*FcHigh)/Fs,"high");

            % Convert ZPK representation to second-order sections.
            % sos_hpf: Biquad section
            % g_hpf: Overall scalar filter gain
            [sos_hpf,g_hpf] = zp2sos(z_hp, p_hp, k_hp);
        end

        function OutputFrame = ProcessHPFFrame(obj, InputFrame)
            %% ==============================================
            %% FRAME-BASED DC-REMOVAL HIGH-PASS FILTERING
            %% ==============================================
            % Each call processes one input frame. The two delay values for
            % every SOS biquad are stored in HPFState and reused by the next
            % call, so frame boundaries do not reset the IIR response.

            ValidFrame = isnumeric(InputFrame) && ...
                isreal(InputFrame) && ...
                (isvector(InputFrame) || isempty(InputFrame)) && ...
                all(isfinite(InputFrame(:)));

            if ~ValidFrame
                error('ADCFilter:InvalidHPFFrame', ...
                    ['InputFrame must be a finite, real-valued ', ...
                     'numeric vector.']);
            end

            % All signal-chain frames use a consistent column orientation.
            InputFrame = double(InputFrame(:));

           % An empty end-of-stream frame produces an empty column and must
           % not initialize or modify the persistent filter state.
            if isempty(InputFrame)
                OutputFrame = zeros(0, 1);
                return
            end

            if ~obj.HPFInitialized
                obj.InitializeHPF();
            end

            % Apply the scalar cascade gain once, before the first section.
            SectionOutput = obj.HPFGain * InputFrame;

            for SectionIndex = 1:size(obj.HPFSOS, 1)
                Numerator = obj.HPFSOS(SectionIndex, 1:3);
                Denominator = obj.HPFSOS(SectionIndex, 4:6);

                [SectionOutput, FinalState] = filter( ...
                    Numerator, ...
                    Denominator, ...
                    SectionOutput, ...
                    obj.HPFState(:, SectionIndex));

                % FinalState from this frame becomes the initial state for
                % the same biquad when the next frame arrives.
                obj.HPFState(:, SectionIndex) = FinalState;
            end

            OutputFrame = SectionOutput;
        end

        function ResetHPF(obj)
            %% ======================================
            %% RESET ALL HPF BIQUAD DELAY ELEMENTS
            %% ======================================
            if obj.HPFInitialized
                NumberSections = size(obj.HPFSOS, 1);
                obj.HPFState = zeros(2, NumberSections);
            else
                obj.HPFState = zeros(2, 0);
            end
        end

        function [sos_lpf, g_lpf] = AAF(obj)

            %% Performs high frequency noise and aliasing removal.
            FcLow = obj.ADCParameters.getValue("FcLow"); % Cutoff Frequency
            Fs = obj.ADCParameters.getValue("Fs");% Sampling Rate
            nLpf = obj.ADCParameters.getValue("nLpf"); % Filter Order

            % Butterworth filter design in Zero-Pole-Gain (ZPK) form.
            [z_lp, p_lp, k_lp] = butter(nLpf, (2*FcLow)/Fs,"low");

            % Convert ZPK representation to second-order sections.
            % sos_lpf: Biquad section
            % g_lpf: Overall scalar filter gain
            [sos_lpf, g_lpf] = zp2sos(z_lp, p_lp, k_lp);
        end

        function OutputFrame = ProcessLPFFrame(obj, InputFrame)
            %% ==============================================
            %% FRAME-BASED ANTI-ALIASING LOW-PASS FILTERING
            %% ==============================================
            % Each call processes one HPF output frame. The two delay values
            % for every LPF SOS biquad are preserved for the next call, so
            % the IIR response remains continuous across frame boundaries.

            ValidFrame = isnumeric(InputFrame) && ...
                isreal(InputFrame) && ...
                (isvector(InputFrame) || isempty(InputFrame)) && ...
                all(isfinite(InputFrame(:)));

            if ~ValidFrame
                error('ADCFilter:InvalidLPFFrame', ...
                    ['InputFrame must be a finite, real-valued ', ...
                     'numeric vector.']);
            end

            % All signal-chain frames use a consistent column orientation.
            InputFrame = double(InputFrame(:));

            % An empty end-of-stream frame produces an empty column and must
            % not initialize or modify the persistent LPF state.
            if isempty(InputFrame)
                OutputFrame = zeros(0, 1);
                return
            end

            if ~obj.LPFInitialized
                obj.InitializeLPF();
            end

            % Apply the scalar cascade gain once, before the first section.
            SectionOutput = obj.LPFGain * InputFrame;

            for SectionIndex = 1:size(obj.LPFSOS, 1)
                Numerator = obj.LPFSOS(SectionIndex, 1:3);
                Denominator = obj.LPFSOS(SectionIndex, 4:6);

                [SectionOutput, FinalState] = filter( ...
                    Numerator, ...
                    Denominator, ...
                    SectionOutput, ...
                    obj.LPFState(:, SectionIndex));

                % FinalState from this frame becomes the initial state for
                % the same LPF biquad when the next frame arrives.
                obj.LPFState(:, SectionIndex) = FinalState;
            end

            OutputFrame = SectionOutput;
        end

        function ResetLPF(obj)
            %% ======================================
            %% RESET ALL LPF BIQUAD DELAY ELEMENTS
            %% ======================================
            if obj.LPFInitialized
                NumberSections = size(obj.LPFSOS, 1);
                obj.LPFState = zeros(2, NumberSections);
            else
                obj.LPFState = zeros(2, 0);
            end
        end
    end

    methods (Access = private)
        function InitializeHPF(obj)
            %% =========================================
            %% DESIGN HPF ONCE AND INITIALIZE SOS STATES
            %% =========================================
            [obj.HPFSOS, obj.HPFGain] = obj.DCRemoval();

            NumberSections = size(obj.HPFSOS, 1);
            obj.HPFState = zeros(2, NumberSections);
            obj.HPFInitialized = true;
        end

        function InitializeLPF(obj)
            %% =========================================
            %% DESIGN LPF ONCE AND INITIALIZE SOS STATES
            %% =========================================
            [obj.LPFSOS, obj.LPFGain] = obj.AAF();

            NumberSections = size(obj.LPFSOS, 1);
            obj.LPFState = zeros(2, NumberSections);
            obj.LPFInitialized = true;
        end
    end
end
