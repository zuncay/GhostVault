// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract MockScheduler {
    struct ScheduledCall { address target; bytes data; }
    uint256 public nextCallId;
    mapping(uint256 => ScheduledCall) private _calls;

    function schedule(bytes memory data, uint32, uint32, uint32, uint32, uint32, uint256, uint256, uint256, address)
        external
        returns (uint256 callId)
    {
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
    fallback(bytes calldata input) external returns (bytes memory) {
        bytes memory output = abi.encode(
            uint16(200), new string[](0), new string[](0),
            bytes('{"last_seen":"2026-07-01","status":"inactive","source":"github"}'), ""
        );
        return abi.encode(input, output);
    }
}

contract MockLLMPrecompile {
    struct StorageRef { string platform; string path; string keyRef; }

    fallback(bytes calldata input) external returns (bytes memory) {
        bytes memory message = abi.encode(
            "assistant", '{"signal":"inactive","confidence":88}', "", uint256(0), new bytes[](0)
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
}

contract MockJQPrecompile {
    fallback(bytes calldata input) external returns (bytes memory) {
        (string memory query,, uint8 outputType) = abi.decode(input, (string, string, uint8));
        if (outputType == 1 && keccak256(bytes(query)) == keccak256(bytes(".confidence"))) {
            return abi.encode(uint256(88));
        }
        return bytes("");
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

