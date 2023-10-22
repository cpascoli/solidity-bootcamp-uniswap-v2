// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// import { IUniswapV2ERC20 } from "./interfaces/IUniswapV2ERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IUniswapV2ERC20 } from "./interfaces/uniswap/IUniswapV2ERC20.sol";

contract UniswapV2ERC20 is ERC20, IUniswapV2ERC20 {

    string public constant NAME = 'Uniswap V2';
    string public constant SYMBOL = 'UNI-V2';

    bytes32 public _DOMAIN_SEPARATOR;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public _nonces;

    constructor() ERC20(NAME, SYMBOL) {
        uint chainId = block.chainid;
        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(NAME)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function DOMAIN_SEPARATOR() public virtual view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    function PERMIT_TYPEHASH() public virtual pure returns (bytes32) {
        return _PERMIT_TYPEHASH;
    }

    function nonces(address owner) public virtual view returns (uint) {
        return _nonces[owner];
    }

    function decimals() public virtual view override(ERC20, IERC20Metadata) returns (uint8) {
        return super.decimals();
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) public virtual {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                _DOMAIN_SEPARATOR,
                keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}