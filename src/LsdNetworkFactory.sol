// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./StakePool.sol";
import "./StakeManager.sol";
import "./LsdToken.sol";
import "./Timelock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ILsdNetworkFactory.sol";

contract LsdNetworkFactory is Initializable, UUPSUpgradeable, ILsdNetworkFactory {
    using SafeERC20 for IERC20;

    address public govStakeManagerAddress;
    address public govOracleAddress;
    address public stakeTokenAddress;

    address public stakeManagerLogicAddress;
    address public stakePoolLogicAddress;

    address public factoryAdmin;
    mapping(address => NetworkContracts) internal networkContractsOfLsdToken;
    mapping(address => address[]) private lsdTokensOf;
    mapping(address => uint256) public totalClaimedLsdToken;

    modifier onlyFactoryAdmin() {
        if (msg.sender != factoryAdmin) {
            revert CallerNotAllowed();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _factoryAdmin,
        address _govStakeManagerAddress,
        address _govOracleAddress,
        address _stakeTokenAddress,
        address _stakeManagerLogicAddress,
        address _stakePoolLogicAddress
    ) external initializer {
        if (_factoryAdmin == address(0)) {
            revert AddressNotAllowed();
        }

        factoryAdmin = _factoryAdmin;
        govStakeManagerAddress = _govStakeManagerAddress;
        govOracleAddress = _govOracleAddress;
        stakeTokenAddress = _stakeTokenAddress;
        stakeManagerLogicAddress = _stakeManagerLogicAddress;
        stakePoolLogicAddress = _stakePoolLogicAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyFactoryAdmin {}

    // ------------ getter ------------

    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function lsdTokensOfCreater(address _creater) public view returns (address[] memory) {
        return lsdTokensOf[_creater];
    }

    function getNetworkContracts(address _lsdToken) public view returns (NetworkContracts memory) {
        return networkContractsOfLsdToken[_lsdToken];
    }

    // ------------ settings ------------

    function transferOwnership(address _newAdmin) public onlyFactoryAdmin {
        if (_newAdmin == address(0)) {
            revert AddressNotAllowed();
        }

        factoryAdmin = _newAdmin;
    }

    function setStakeManagerLogicAddress(address _stakeManagerLogicAddress) public onlyFactoryAdmin {
        stakeManagerLogicAddress = _stakeManagerLogicAddress;
    }

    function setStakePoolLogicAddress(address _stakePoolLogicAddress) public onlyFactoryAdmin {
        stakePoolLogicAddress = _stakePoolLogicAddress;
    }

    function factoryClaim(address _lsdToken, address _recipient, uint256 _amount) external onlyFactoryAdmin {
        IERC20(_lsdToken).safeTransfer(_recipient, _amount);
        totalClaimedLsdToken[_lsdToken] += _amount;
    }

    // ------------ user ------------

    function createLsdNetwork(
        string memory _lsdTokenName,
        string memory _lsdTokenSymbol,
        address _govInstantManagerAddress,
        address _govOracleAddress
    ) external override {
        _createLsdNetwork(_lsdTokenName, _lsdTokenSymbol, _govInstantManagerAddress, _govOracleAddress, msg.sender);
    }

    function createLsdNetworkWithTimelock(
        string memory _lsdTokenName,
        string memory _lsdTokenSymbol,
        address _govInstantManagerAddress,
        address _govOracleAddress,
        uint256 minDelay,
        address[] memory proposers
    ) external override {
        address networkAdmin = address(new Timelock(minDelay, proposers, proposers, msg.sender));
        _createLsdNetwork(_lsdTokenName, _lsdTokenSymbol, _govInstantManagerAddress, _govOracleAddress, networkAdmin);
    }

    // ------------ helper ------------

    function _createLsdNetwork(
        string memory _lsdTokenName,
        string memory _lsdTokenSymbol,
        address _govInstantManagerAddress,
        address _govOracleAddress,
        address _networkAdmin
    ) private {
        NetworkContracts memory contracts = deployNetworkContracts(_lsdTokenName, _lsdTokenSymbol);

        networkContractsOfLsdToken[contracts._lsdToken] = contracts;
        lsdTokensOf[msg.sender].push(contracts._lsdToken);

        (bool success, bytes memory data) = contracts._stakePool.call(
            abi.encodeWithSelector(
                StakePool.initialize.selector,
                contracts._stakeManager,
                _govInstantManagerAddress,
                _govOracleAddress,
                _networkAdmin
            )
        );
        if (!success) {
            revert FailedToCall();
        }

        (success, data) = contracts._stakeManager.call(
            abi.encodeWithSelector(
                StakeManager.initialize.selector, contracts._lsdToken, contracts._stakePool, _networkAdmin, this
            )
        );
        if (!success) {
            revert FailedToCall();
        }

        (success, data) =
            contracts._lsdToken.call(abi.encodeWithSelector(ILsdToken.initMinter.selector, contracts._stakeManager));
        if (!success) {
            revert FailedToCall();
        }

        emit LsdNetwork(contracts);
    }

    function deploy(address _logicAddress) private returns (address) {
        return address(new ERC1967Proxy(_logicAddress, ""));
    }

    function deployNetworkContracts(string memory _lsdTokenName, string memory _lsdTokenSymbol)
        private
        returns (NetworkContracts memory)
    {
        address stakeManager = deploy(stakeManagerLogicAddress);
        address stakePool = deploy(stakePoolLogicAddress);

        address lsdToken = address(new LsdToken(_lsdTokenName, _lsdTokenSymbol));

        return NetworkContracts(stakeManager, stakePool, lsdToken, block.number);
    }
}
