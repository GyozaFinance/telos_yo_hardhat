// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./helpers/Governable.sol";

/**@title StratShojiru
 * @notice This contract keeps tokens safe for the masterchef and allows for more complex strategies if needed
**/
contract StratShojiru is Ownable, ReentrancyGuard, Pausable, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable wantAddress;
    address public immutable shojiruFarmAddress;

    // Total want tokens managed by strategy
    uint256 public wantLockedTotal = 0;

    // Sum of all shares of users to wantLockedTotal
    uint256 public sharesTotal = 0;

    uint256 public entranceFeeFactor = 10000; // No deposit fees
    uint256 public constant entranceFeeFactorMax = 10000;
    uint256 public constant entranceFeeFactorLL = 9950; // 0.5% is the max entrance fee settable. LL = lowerlimit

    uint256 public withdrawFeeFactor = 10000; // No withdraw fees
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9950; // 0.5% is the max entrance fee settable. LL = lowerlimit

    event SetSettings(uint256 _entranceFeeFactor, uint256 _withdrawFeeFactor);

    constructor (address _shojiru, address _shojiruFarmAddress, address _govAddress) public {
        wantAddress = _shojiru;
        shojiruFarmAddress = _shojiruFarmAddress;
        govAddress = _govAddress;
        transferOwnership(_shojiruFarmAddress);
    }

    /// @dev This contract doesn't auto-compound
    /// @notice earn() function is here to follow the Strategy interface
    function earn() external {}

    /// @notice Transfer want tokens shojiruFarm -> strategy
    function deposit(
        uint256 _wantAmt
    ) external virtual onlyOwner nonReentrant whenNotPaused returns (uint256) {
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        uint256 sharesAdded = _wantAmt;

        if (wantLockedTotal > 0 && sharesTotal > 0) {
            sharesAdded = _wantAmt
            .mul(sharesTotal)
            .mul(entranceFeeFactor)
            .div(wantLockedTotal)
            .div(entranceFeeFactorMax);
        }

        sharesTotal = sharesTotal.add(sharesAdded);

        wantLockedTotal = wantLockedTotal.add(_wantAmt);

        return sharesAdded;
    }

    /// @notice Transfer want tokens strategy -> shojiruFarm
    function withdraw(
        uint256 _wantAmt
    ) external virtual onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt <= 0");

        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);

        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }

        sharesTotal = sharesTotal.sub(sharesRemoved);

        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));

        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        IERC20(wantAddress).safeTransfer(shojiruFarmAddress, _wantAmt);

        return sharesRemoved;
    }

    /// @notice In case some tokens get sent here by mistake
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external virtual onlyAllowGov {
        require(_token != wantAddress, "!safe");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Change entrance/withdraw fees
    function setSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor
    ) external virtual onlyAllowGov {
        require(
            _entranceFeeFactor >= entranceFeeFactorLL,
            "_entranceFeeFactor too low"
        );
        require(
            _entranceFeeFactor <= entranceFeeFactorMax,
            "_entranceFeeFactor too high"
        );
        entranceFeeFactor = _entranceFeeFactor;

        require(
            _withdrawFeeFactor >= withdrawFeeFactorLL,
            "_withdrawFeeFactor too low"
        );
        require(
            _withdrawFeeFactor <= withdrawFeeFactorMax,
            "_withdrawFeeFactor too high"
        );
        withdrawFeeFactor = _withdrawFeeFactor;

        emit SetSettings(_entranceFeeFactor, _withdrawFeeFactor);
    }
}
