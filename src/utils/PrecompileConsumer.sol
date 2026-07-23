// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract PrecompileConsumer {
    address internal constant HTTP_CALL_PRECOMPILE = address(0x0801);
    address internal constant LLM_INFERENCE_PRECOMPILE = address(0x0802);
    address internal constant JQ_PRECOMPILE = address(0x0904);

    function _executePrecompile(address target, bytes memory input)
        internal
        returns (bytes memory output)
    {
        (bool ok, bytes memory raw) = target.call(input);
        require(ok, "precompile call failed");
        (, output) = abi.decode(raw, (bytes, bytes));
    }
}

