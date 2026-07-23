// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract MockScheduler {
    struct ScheduledCall { address target; bytes data; }
    uint256 public nextCallId;
    mapping(uint256 => ScheduledCall) private _calls;

    function schedule(bytes memory data, uint32, uint32 startBlock, uint32 numCalls, uint32 frequency, uint32 ttl, uint256, uint256, uint256, address)
        external
        returns (uint256 callId)
    {
        require(ttl <= 500, "InvalidTTL");
        require(
            uint256(startBlock - block.number) + uint256(numCalls) * frequency < 10_000,
            "ScheduleLifespanExceeded"
        );
        callId = ++nextCallId;
        _calls[callId] = ScheduledCall(msg.sender, data);
    }

    function trigger(uint256 callId, uint256 executionIndex) external {
        ScheduledCall memory scheduled = _calls[callId];
        require(scheduled.target != address(0), "missing call");
        bytes memory data = scheduled.data;
        assembly { mstore(add(data, 36), executionIndex) }
        (bool ok, bytes memory reason) = scheduled.target.call(data);
        if (!ok) assembly { revert(add(reason, 32), mload(reason)) }
    }

    function cancel(uint256 callId) external { delete _calls[callId]; }
    function getCallState(uint256) external pure returns (uint8) { return 0; }
}

contract MockTEERegistry {
    function pickServiceByCapability(uint8 capability, bool, uint256, uint256)
        external
        pure
        returns (address teeAddress, bool found)
    {
        return (capability == 0 ? address(0x8011) : address(0x8022), true);
    }
}

contract MockHTTPPrecompile {
    bool public failRequest;

    function configure(bool shouldFail) external { failRequest = shouldFail; }

    fallback(bytes calldata input) external returns (bytes memory) {
        bytes memory output = abi.encode(
            failRequest ? uint16(503) : uint16(200), new string[](0), new string[](0),
            failRequest ? bytes("") : bytes('{"last_seen":"2026-07-01","status":"inactive","source":"github"}'),
            failRequest ? "upstream unavailable" : ""
        );
        return abi.encode(input, output);
    }
}

contract MockLLMPrecompile {
    struct StorageRef { string platform; string path; string keyRef; }
    string public configuredSignal;
    uint256 public configuredConfidence;
    bool public failInference;

    function configure(string calldata signal, uint256 confidence, bool shouldFail) external {
        configuredSignal = signal;
        configuredConfidence = confidence;
        failInference = shouldFail;
    }

    fallback(bytes calldata input) external returns (bytes memory) {
        if (failInference) {
            bytes memory failed = abi.encode(true, bytes(""), bytes(""), "model unavailable", StorageRef("", "", ""));
            return abi.encode(input, failed);
        }
        string memory signal = bytes(configuredSignal).length == 0 ? "inactive" : configuredSignal;
        uint256 confidence = configuredConfidence == 0 ? 88 : configuredConfidence;
        bytes memory message = abi.encode(
            "assistant",
            string.concat('{"signal":"', signal, '","confidence":', _toString(confidence), "}"),
            "",
            uint256(0),
            new bytes[](0)
        );
        bytes[] memory choices = new bytes[](1);
        choices[0] = abi.encode(uint256(0), "stop", message);
        bytes memory completion = abi.encode(
            "ghost-completion", "chat.completion", uint256(1), "zai-org/GLM-4.7-FP8", "", "default",
            uint256(1), choices, abi.encode(uint256(10), uint256(5), uint256(15))
        );
        bytes memory output = abi.encode(false, completion, bytes(""), "", StorageRef("", "", ""));
        return abi.encode(input, output);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temporary = value;
        uint256 digits;
        while (temporary != 0) { ++digits; temporary /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) { --digits; buffer[digits] = bytes1(uint8(48 + value % 10)); value /= 10; }
        return string(buffer);
    }
}

contract MockJQPrecompile {
    string public configuredSignal;
    uint256 public configuredConfidence;

    function configure(string calldata signal, uint256 confidence) external {
        configuredSignal = signal;
        configuredConfidence = confidence;
    }

    fallback(bytes calldata input) external returns (bytes memory) {
        (string memory query,, uint8 outputType) = abi.decode(input, (string, string, uint8));
        if (outputType == 1 && keccak256(bytes(query)) == keccak256(bytes(".confidence"))) {
            return abi.encode(configuredConfidence == 0 ? uint256(88) : configuredConfidence);
        }
        if (outputType == 2 && keccak256(bytes(query)) == keccak256(bytes(".signal"))) {
            return _encodeJQString(bytes(configuredSignal).length == 0 ? "inactive" : configuredSignal);
        }
        return bytes("");
    }

    function _encodeJQString(string memory value) internal pure returns (bytes memory raw) {
        bytes memory characters = bytes(value);
        raw = new bytes(96 + characters.length);
        uint256 length = characters.length;
        assembly { mstore(add(raw, 96), length) }
        for (uint256 i; i < length; ++i) raw[96 + i] = characters[i];
    }
}

contract MockRitualWallet {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public lockUntil;

    function deposit(uint256 lockDuration) external payable {
        balanceOf[msg.sender] += msg.value;
        lockUntil[msg.sender] = block.number + lockDuration;
    }
}
