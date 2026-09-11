classdef ADCEncoder
    %% ==============================================
    %% ADC OFFSET-BINARY AND TWO'S-COMPLEMENT ENCODER
    %% ==============================================
   
    properties (SetAccess = private)
        ADCParameters
        NumBits
    end

    methods
        function obj = ADCEncoder(P)
            %% ============================
            %% ENCODER INSTANCE CONSTRUCTOR
            %% ============================

            obj.ADCParameters = P;
            obj.NumBits = P.getValue("NumBits");
        end

        function [OffsetBinary, TwosComplement,InputFormat] = ...
            Encode(obj, Indices)
            %% =========================================================
            %% OFFSET-BINARY AND TWO'S-COMPLEMENT NUMERICAL ENCODING
            %% =========================================================

            NumBits = obj.NumBits;

            % Validate ADC quantizer indices
            obj.ValidateIndices(Indices);

            %% -----------------------------
            %% OFFSET-BINARY REPRESENTATION
            %% -----------------------------

            OffsetBinary = obj.CastUnsignedCode(Indices);

            %% ------------------------------------------
            %% TWO'S-COMPLEMENT REPRESENTATION
            %% ------------------------------------------
 
            if NumBits < 64

                HalfScale = bitshift(int64(1), NumBits - 1);

                SignedIntegers = int64(Indices) - HalfScale;

                TwosComplement = ...
                    obj.CastSignedCode(SignedIntegers);

            else

                %% --------------------------------------
                %% SPECIAL 64-BIT CASE
                %% --------------------------------------

                MSBMask = bitshift(uint64(1), 63);

                RawTwos = bitxor(uint64(OffsetBinary), ...
                                 MSBMask);

                OriginalSize = size(RawTwos);

                TwosComplement = typecast( ...
                    RawTwos(:), 'int64');

                TwosComplement = reshape( ...
                    TwosComplement, OriginalSize);

            end

            %% ------------------------------------------
            %% ADC INTEGER CODE FORMAT
            %% ------------------------------------------
            % Both representations are integer code streams. Return the
            % format for every supported ADC width so the downstream
            % fixed-point decimator receives explicit scaling metadata.

            InputFormat.WL  = NumBits;
            InputFormat.IWL = NumBits;
            InputFormat.FWL = 0;
        end

        function [OffsetBits, TwosBits] = Binary(obj, ...
                OffsetBinary, TwosComplement)
            %% ===========================================
            %% DISPLAY BIT-ACCURATE BINARY REPRESENTATION
            %% ===========================================
           
            NumBits = obj.NumBits;

            % Exact logical Offset-Binary representation
            OffsetBits = obj.ExtractLogicalBits( ...
                OffsetBinary, NumBits);

            % Exact logical Two's-Complement representation
            TwosBits = obj.ExtractLogicalBits( ...
                TwosComplement, NumBits);
        end
    end

    methods (Access = private)
        function ValidateIndices(obj, Indices)
            %% ===============================
            %% VALIDATE ADC QUANTIZER INDICES
            %% ===============================

            NumBits = obj.NumBits;

            % For ADC widths greater than 53 bits, require uint64
            % indices so that the codeword remains bit-accurate.

            if NumBits > 53 && isfloat(Indices)

                error('ADCEncoder:PrecisionLoss', ...
                    ['For ADC widths greater than 53 bits, ' ...
                     'quantizer indices must use uint64 ' ...
                     'to preserve exact integer codewords.']);
            end

            %% --------------------------------
            %% FLOATING-POINT INPUT VALIDATION
            %% --------------------------------

            if isfloat(Indices)
                if any(~isfinite(Indices(:))) || ...
                   any(Indices(:) ~= fix(Indices(:)))

                    error('ADCEncoder:InvalidIndex', ...
                        'Quantizer indices must be finite integers.');
                end

                MinIndex = 0;
                MaxIndex = (2^NumBits) - 1;

                if any(Indices(:) < MinIndex) || ...
                   any(Indices(:) > MaxIndex)

                    error('ADCEncoder:IndexOutOfRange', ...
                        ['Quantizer index must lie between 0 and ' ...
                         '2^NumBits - 1.']);
                end

            %% ------------------------
            %% INTEGER INPUT VALIDATION
            %% ------------------------

            elseif isinteger(Indices)

                % Reject negative signed integer indices
                if any(Indices(:) < 0)

                    error('ADCEncoder:IndexOutOfRange', ...
                        'Quantizer indices cannot be negative.');
                end

                % Exact maximum codeword
                if NumBits == 64

                    MaxIndex = intmax('uint64');
                else

                    MaxIndex = ...
                        bitshift(uint64(1), NumBits) - uint64(1);
                end

                if any(uint64(Indices(:)) > MaxIndex)

                    error('ADCEncoder:IndexOutOfRange', ...
                        ['Quantizer index exceeds the maximum ' ...
                         'codeword for the configured ADC width.']);
                end
            else

                error('ADCEncoder:InvalidDatatype', ...
                    'Quantizer indices must be numeric integers.');
            end
        end

        function UnsignedCodeword = CastUnsignedCode(obj, OffsetBinary)
            %% =========================================================
            %% ADC QUANTIZER INDICES TO UNSIGNED INTEGER DATATYPE
            %% =========================================================

            NumBits = obj.NumBits;

            if NumBits <= 8

                UnsignedCodeword = uint8(OffsetBinary);

            elseif NumBits <= 16

                UnsignedCodeword = uint16(OffsetBinary);

            elseif NumBits <= 32

                UnsignedCodeword = uint32(OffsetBinary);

            else

                UnsignedCodeword = uint64(OffsetBinary);
            end
        end

        function SignedCodeword = CastSignedCode(obj, TwosComplement)
            %% =========================================================
            %% SIGNED VALUE TO SIGNED INTEGER STORAGE DATATYPE
            %% =========================================================
 
          NumBits = obj.NumBits;

            if NumBits <= 8

                SignedCodeword = int8(TwosComplement);

            elseif NumBits <= 16

                SignedCodeword = int16(TwosComplement);

            elseif NumBits <= 32

                SignedCodeword = int32(TwosComplement);

            else

                SignedCodeword = int64(TwosComplement);
            end
        end

        function Bits = ExtractLogicalBits(~, Values, NumBits)
            %% ==================================
            %% EXTRACT EXACT LOGICAL WORD LENGTH
            %% ==================================
            %
            % MATLAB may store, for example, a 12-bit ADC code inside
            % uint16/int16. This helper extracts only:
            %
            %       Bit NumBits ... Bit 2, Bit 1
            %
            % Therefore the returned bit representation always matches
            % the configured ADC word length.

            Values = Values(:);

            NumValues = numel(Values);

            % Preallocate character matrix:
            %
            %       rows    = ADC samples
            %       columns = logical ADC bits

            Bits = repmat('0', NumValues, NumBits);

            % Read from logical MSB down to LSB
            for Column = 1:NumBits

                BitPosition = NumBits - Column + 1;

                CurrentBit = bitget(Values, BitPosition);

                Bits(:, Column) = ...
                    char(double(CurrentBit) + double('0'));
            end
        end
    end
end
