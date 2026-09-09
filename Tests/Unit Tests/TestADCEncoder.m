classdef TestADCEncoder < matlab.unittest.TestCase
    %% =========================
    %% UNIT TESTS FOR ADCEncoder
    %% =========================
    %
    % Verifies:
    %
    %   1. 8-bit Offset Binary numerical encoding
    %   2. 8-bit Two's Complement numerical encoding
    %   3. Exact 8-bit binary representations
    %   4. Complete 8-bit ADC code range
    %   5. 10-bit logical word length
    %   6. 20-bit logical word length
    %   7. 64-bit logical word length
    %   8. Correct MATLAB storage datatype
    %   9. ADC midpoint-to-zero mapping
    %  10. Invalid negative index rejection
    %  11. Above-range index rejection
    %
    % Important distinction:
    %
    % MATLAB storage width is not necessarily equal to the logical
    % ADC word length.
    %
    % Example:
    %
    %       12-bit ADC
    %           |
    %           +--> uint16 Offset Binary storage
    %           +--> int16 Two's Complement storage
    %
    % Binary() must still return exactly 12 bits.

    methods (Test)
        function test8BitNumericalEncoding(testCase)
            %% =================================
            %% TEST : 8-BIT NUMERICAL ENCODING
            %% =================================

            Encoder = testCase.CreateEncoder(8);

            Indices = [0, 1, 64, 127, 128, 129, 254, 255];

            [OffsetBinary, TwosComplement] = ...
                Encoder.Encode(Indices);


            ExpectedOffset = uint8( ...
                [0, 1, 64, 127, 128, 129, 254, 255]);

            ExpectedTwos = int8( ...
                [-128, -127, -64, -1, 0, 1, 126, 127]);


            testCase.verifyEqual(OffsetBinary, ExpectedOffset);

            testCase.verifyEqual(TwosComplement, ExpectedTwos);

        end

        function test8BitStorageDatatype(testCase)
            %% =================================
            %% TEST : 8-BIT STORAGE DATATYPES
            %% =================================

            Encoder = testCase.CreateEncoder(8);

            Indices = [0, 127, 128, 255];

            [OffsetBinary, TwosComplement] = ...
                Encoder.Encode(Indices);

            % Offset Binary is unsigned
            testCase.verifyClass(OffsetBinary, 'uint8');

            % Two's Complement arithmetic representation is signed
            testCase.verifyClass(TwosComplement, 'int8');
        end

        function test8BitBinaryRepresentation(testCase)
            %% ===================================
            %% TEST : 8-BIT BINARY REPRESENTATION
            %% ===================================

            Encoder = testCase.CreateEncoder(8);

            Indices = [0, 1, 64, 127, 128, 129, 254, 255];

            [OffsetBinary, TwosComplement] = ...
                Encoder.Encode(Indices);

            [OffsetBits, TwosBits] = ...
                Encoder.Binary(OffsetBinary, TwosComplement);

            ExpectedOffsetBits = [
                "00000000"
                "00000001"
                "01000000"
                "01111111"
                "10000000"
                "10000001"
                "11111110"
                "11111111"
            ];

            ExpectedTwosBits = [
                "10000000"
                "10000001"
                "11000000"
                "11111111"
                "00000000"
                "00000001"
                "01111110"
                "01111111"
            ];

            testCase.verifyEqual( ...
                string(OffsetBits), ExpectedOffsetBits);

            testCase.verifyEqual( ...
                string(TwosBits), ExpectedTwosBits);
        end

        function test8BitLogicalWordLength(testCase)
            %% =================================
            %% TEST : 8-BIT LOGICAL WORD LENGTH
            %% ==================================

            Encoder = testCase.CreateEncoder(8);

            Indices = [0, 127, 128, 255];

            [OffsetBinary, TwosComplement] = ...
                Encoder.Encode(Indices);

            [OffsetBits, TwosBits] = ...
                Encoder.Binary(OffsetBinary, TwosComplement);

            % Number of binary columns must equal ADC word length
            testCase.verifyEqual(size(OffsetBits, 2), 8);

            testCase.verifyEqual(size(TwosBits, 2), 8);
        end

        function testComplete8BitCodeRange(testCase)
            %% ======================================
            %% TEST : COMPLETE 8-BIT ADC CODE RANGE
            %% =======================================
            %
            % Verify all 256 possible quantizer indices.

            Encoder = testCase.CreateEncoder(8);

            Indices = 0:255;

            [OffsetBinary, TwosComplement] = ...
                Encoder.Encode(Indices);

            ExpectedOffset = uint8(0:255);

            ExpectedTwos = int8(-128:127);

            testCase.verifyEqual( ...
                OffsetBinary, ExpectedOffset);

            testCase.verifyEqual( ...
                TwosComplement, ExpectedTwos);
        end

        function test10BitLogicalWordLength(testCase)
            %% =========================================
            %% TEST : 10-BIT ADC WORD LENGTH
            %% =========================================
            %
            % MATLAB has no int10/uint10 datatype.
            %
            % Therefore:
            %
            %       Offset Binary      -> uint16
            %       Two's Complement   -> int16
            %
            % But Binary() must return exactly 10 bits.

            Encoder = testCase.CreateEncoder(10);

            Indices = [0, 511, 512, 1023];

            [OffsetBinary, TwosComplement] = ...
                Encoder.Encode(Indices);

            [OffsetBits, TwosBits] = ...
                Encoder.Binary(OffsetBinary, TwosComplement);

            ExpectedOffset = ...
                uint16([0, 511, 512, 1023]);

            ExpectedTwos = ...
                int16([-512, -1, 0, 511]);

            ExpectedOffsetBits = [
                "0000000000"
                "0111111111"
                "1000000000"
                "1111111111"
            ];

            ExpectedTwosBits = [
                "1000000000"
                "1111111111"
                "0000000000"
                "0111111111"
            ];

            % Numerical mapping
            testCase.verifyEqual( ...
                OffsetBinary, ExpectedOffset);

            testCase.verifyEqual( ...
                TwosComplement, ExpectedTwos);

            % MATLAB storage datatype
            testCase.verifyClass(OffsetBinary, 'uint16');

            testCase.verifyClass(TwosComplement, 'int16');

            % Exact bit representation
            testCase.verifyEqual( ...
                string(OffsetBits), ExpectedOffsetBits);

            testCase.verifyEqual( ...
                string(TwosBits), ExpectedTwosBits);

            % Logical ADC width
            testCase.verifyEqual(size(OffsetBits, 2), 10);

            testCase.verifyEqual(size(TwosBits, 2), 10);
        end

        function test20BitLogicalWordLength(testCase)
            %% ==============================
            %% TEST : 20-BIT ADC WORD LENGTH
            %% ==============================
            %
            % This verifies the important distinction:
            %
            %       MATLAB storage = 32 bits
            %
            %       ADC word length = 20 bits

            Encoder20 = testCase.CreateEncoder(20);
            HalfScale20 = bitshift(uint32(1), 19);
            MaxCode20   = bitshift(uint32(1), 20) - uint32(1);
            Indices20 = [ ...
                uint32(0), ...
                HalfScale20 - uint32(1), ...
                HalfScale20, ...
                MaxCode20 ...
                ];
            [Offset20, Twos20] = ...
                Encoder20.Encode(Indices20);

            [OffsetBits20, TwosBits20] = ...
                Encoder20.Binary(Offset20, Twos20);
            
            ExpectedOffset20 = Indices20;
            
            ExpectedTwos20 = int32([ ...
                -524288, ...
                -1, ...
                0, ...
                524287 ...
                ]);

            %% Numerical mapping
            testCase.verifyEqual( ...
                Offset20, ExpectedOffset20);

            testCase.verifyEqual( ...
                Twos20, ExpectedTwos20);
            %% MATLAB storage datatype
            testCase.verifyClass(Offset20, 'uint32');
            
            testCase.verifyClass(Twos20, 'int32');

            %% Logical ADC width
            testCase.verifyEqual( ...
                size(OffsetBits20, 2), 20);

            testCase.verifyEqual( ...
                size(TwosBits20, 2), 20);
            
            %% Important boundary bit patterns
            ExpectedOffsetBits20 = [
                string(repmat('0', 1, 20))
                "0" + string(repmat('1', 1, 19))
                "1" + string(repmat('0', 1, 19))
                string(repmat('1', 1, 20))
                ];
            
            ExpectedTwosBits20 = [
                "1" + string(repmat('0', 1, 19))
                string(repmat('1', 1, 20))
                string(repmat('0', 1, 20))
                "0" + string(repmat('1', 1, 19))
                ];
            
            testCase.verifyEqual( ...
                string(OffsetBits20), ExpectedOffsetBits20);
            
            testCase.verifyEqual( ...
                string(TwosBits20), ExpectedTwosBits20);
        end

        function test64BitWordLengths(testCase)
            %% ============
            %% 64-BIT ADC
            %% ===========

            Encoder64 = testCase.CreateEncoder(64);

            % IMPORTANT:
            % Do not construct these values using 2^63 or 2^64
            % as doubles. Use uint64 bit operations instead.

            HalfScale64 = bitshift(uint64(1), 63);
            MaxCode64   = intmax('uint64');

            Indices64 = [ ...
                uint64(0), ...
                HalfScale64 - uint64(1), ...
                HalfScale64, ...
                MaxCode64 ...
                ];

            [Offset64, Twos64] = ...
                Encoder64.Encode(Indices64);

            [OffsetBits64, TwosBits64] = ...
                Encoder64.Binary(Offset64, Twos64);

            ExpectedOffset64 = Indices64;

            ExpectedTwos64 = [ ...
                intmin('int64'), ...
                int64(-1), ...
                int64(0), ...
                intmax('int64') ...
                ];

            %% Numerical mapping

            testCase.verifyEqual( ...
                Offset64, ExpectedOffset64);

            testCase.verifyEqual( ...
                Twos64, ExpectedTwos64);


            %% MATLAB storage datatype

            testCase.verifyClass(Offset64, 'uint64');

            testCase.verifyClass(Twos64, 'int64');


            %% Exact 64-bit logical word length

            testCase.verifyEqual( ...
                size(OffsetBits64, 2), 64);

            testCase.verifyEqual( ...
                size(TwosBits64, 2), 64);


            %% Important 64-bit boundary patterns

            ExpectedOffsetBits64 = [
                string(repmat('0', 1, 64))
                "0" + string(repmat('1', 1, 63))
                "1" + string(repmat('0', 1, 63))
                string(repmat('1', 1, 64))
                ];

            ExpectedTwosBits64 = [
                "1" + string(repmat('0', 1, 63))
                string(repmat('1', 1, 64))
                string(repmat('0', 1, 64))
                "0" + string(repmat('1', 1, 63))
                ];

            testCase.verifyEqual( ...
                string(OffsetBits64), ExpectedOffsetBits64);

            testCase.verifyEqual( ...
                string(TwosBits64), ExpectedTwosBits64);
        end

        function testMidpointMapsToSignedZero(testCase)
            %% ========================================
            %% TEST : ADC MIDPOINT MAPS TO SIGNED ZERO
            %% ========================================
            %
            % For an N-bit bipolar ADC:
            %
            %       Index = 2^(N-1)
            %
            % maps to:
            %
            %       Signed value = 0

            NumBits = 8;

            Encoder = testCase.CreateEncoder(NumBits);

            MidPointIndex = 2^(NumBits - 1);

            [~, TwosComplement] = ...
                Encoder.Encode(MidPointIndex);


            testCase.verifyEqual( ...
                TwosComplement, int8(0));
        end

        function testBoundaryMappings(testCase)
            %% ===============================
            %% TEST : 8-BIT BOUNDARY MAPPINGS
            %% ===============================

            Encoder = testCase.CreateEncoder(8);

            Indices = [0, 127, 128, 255];

            [OffsetBinary, TwosComplement] = ...
                Encoder.Encode(Indices);

            [OffsetBits, TwosBits] = ...
                Encoder.Binary(OffsetBinary, TwosComplement);


            ExpectedOffsetBits = [
                "00000000"
                "01111111"
                "10000000"
                "11111111"
            ];

            ExpectedTwosBits = [
                "10000000"
                "11111111"
                "00000000"
                "01111111"
            ];

            ExpectedSigned = ...
                int8([-128, -1, 0, 127]);


            testCase.verifyEqual( ...
                string(OffsetBits), ExpectedOffsetBits);

            testCase.verifyEqual( ...
                string(TwosBits), ExpectedTwosBits);

            testCase.verifyEqual( ...
                TwosComplement, ExpectedSigned);
        end

        function testNegativeIndexRejected(testCase)
            %% ===========================================
            %% TEST: NEGATIVE QUANTIZER INDEX REJECTION
            %% ===========================================

            Encoder = testCase.CreateEncoder(8);

            InvalidIndices = [-1, 0, 1];

            DidThrowError = false;

            try
                Encoder.Encode(InvalidIndices);

            catch
                DidThrowError = true;
            end

            testCase.verifyTrue( ...
                DidThrowError, ...
                "ADCEncoder accepted a negative quantizer index.");
        end

        function testAboveRangeIndexRejected(testCase)
            %% ==============================================
            %% TEST : ABOVE-RANGE QUANTIZER INDEX REJECTION
            %% ==============================================

            Encoder = testCase.CreateEncoder(8);

            InvalidIndices = [0, 255, 256];

            DidThrowError = false;

            try
                Encoder.Encode(InvalidIndices);

            catch
                DidThrowError = true;
            end

            testCase.verifyTrue( ...
                DidThrowError, ...
                "ADCEncoder accepted an index above the ADC range.");
        end
    end

    methods (Access = private)
        function Encoder = CreateEncoder(~, NumBits)
            %% ===================================
            %% ADCEncoder TEST INSTANCE GENERATOR
            %% ===================================
            %
            % Creates an independent Parameters object for each test
            % and configures the requested ADC resolution.

            P = ADCParameters();

            P.setValue("NumBits", NumBits);

            Encoder = ADCEncoder(P);
        end
    end
end