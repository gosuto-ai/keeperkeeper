# @version 0.3.7
"""
@title KeeperKeeper
@author gosuto.eth
@license GPL
@notice Register Chainlink upkeeps for a swarm of smart contracts and
        automatically maintain the $LINK balance for each individual member
@dev WIP, not deployed yet!
"""

# from interfaces import ISwapRouter


# external interfaces
interface IERC677:
    def balanceOf(_owner: address) -> uint256: view
    def transferAndCall(_to: address, _value: uint256, _data: Bytes[388]) -> bool: nonpayable

interface IAutomationRegistry:
    # https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/interfaces/AutomationRegistryInterface1_3.sol
    def getState() -> (State, Config, address[1]): view

interface IKeeperRegistrar:
    def register(
        name: String[64],
        encryptedEmail: bytes32,
        upkeepContract: address,
        gasLimit: uint32,
        adminAddress: address,
        checkData: bytes32,
        amount: uint96,
        source: uint8,
        sender: address
    ) -> uint256: nonpayable


# structs
struct Config:  # IAutomationRegistry
    paymentPremiumPPB: uint32
    flatFeeMicroLink: uint32  # min 0.000001 LINK, max 4294 LINK
    blockCountPerTurn: uint24
    checkGasLimit: uint32
    stalenessSeconds: uint24
    gasCeilingMultiplier: uint16
    minUpkeepSpend: uint96
    maxPerformGas: uint32
    fallbackGasPrice: uint256
    fallbackLinkPrice: uint256
    transcoder: address
    registrar: address

struct State:  # IAutomationRegistry
    nonce: uint32
    ownerLinkBalance: uint96
    expectedLinkBalance: uint256
    numUpkeeps: uint256


# events
event LinkSwappedIn:
    amount: uint256

event LinkSwappedOut:
    amount: uint256


# constants
MAX_SWARM_SIZE: constant(uint8) = 16

LINK: constant(address) = 0x514910771AF9Ca656af840dff83E8264EcF986CA
CL_REGISTRY: constant(address) = 0x02777053d6764996e594c3E88AF1D58D5363a2e6
CL_REGISTRAR: constant(address) = 0xDb8e8e2ccb5C033938736aa89Fe4fa1eDfD15a1d
UNIV3_ROUTER: constant(address) = 0xE592427A0AEce92De3Edee1F18E0157C05861564


# storage vars
swarm: public(uint32[MAX_SWARM_SIZE])


@payable
@external
def __init__():
    """
    @notice Contract constructor
    """
    if not self._enough_link():
        self._swap_link_in()
    upkeep_id: uint32 = self._register_member(self, "KeeperKeeper", 1_000_000)

    # add new upkeep id to swarm
    self.swarm[0] = upkeep_id


@internal
def _register_member(member: address, name: String[64], gas_limit: uint32) -> uint32:
    """
    @notice Register an upkeep on the automation registrar and predict its id
    @params member Address of the member to register in the swarm
    @params name Name of the upkeep
    @params gas_limit Max gas that the member's performUpkeep will need
    @dev https://docs.chain.link/chainlink-automation/register-upkeep/
    """
    # get old nonce from registry
    state: State = IAutomationRegistry(CL_REGISTRY).getState()[0]
    old_nonce: uint32 = state.nonce

    # build registration payload and send to registrar via erc677
    # payload: Bytes[388] = _abi_encode(
    #     name,
    #     empty(bytes32),
    #     self,
    #     gas_limit,
    #     self,
    #     empty(bytes32),
    #     self._threshold(),
    #     empty(uint256),
    #     self,
    #     method_id=0x3659d666  # method_id("register(String[64],bytes32,address,uint32,address,bytes32,uint96,uint8,address)")
    # )
    # IERC677(LINK).transferAndCall(CL_REGISTRAR, self._threshold(), empty(Bytes[388]))#payload)

    # get new nonce from registry
    state = IAutomationRegistry(CL_REGISTRY).getState()[0]
    new_nonce: uint32 = state.nonce
    if not new_nonce == old_nonce + 1:
        raise

    # predict upkeep id
    upkeep_hash: bytes32 = keccak256(
        concat(
            blockhash(block.number - 1),
            convert(CL_REGISTRY, bytes32),
            convert(old_nonce, bytes32)
        )
    )
    upkeep_id: uint32 = convert(upkeep_hash, uint32)

    return upkeep_id


@view
@internal
def _enough_link() -> bool:
    """"
    Check if KeeperKeeper's $LINK's balance is above threshold
    """
    if IERC677(LINK).balanceOf(self) >= 5 * 10 ** 18:  # self._threshold():
        return True
    return False


@view
@internal
def _threshold() -> uint256:
    """
    Minimum amount of $LINK needed for a single swarm member
    """
    # TODO: calculate dynamically based on gas oracle
    threshold: uint256 = 100 * 10 ** 18
    hardcoded: uint256 = 5 * 10 ** 18
    return max(threshold, hardcoded)


@payable
@internal
def _swap_link_in():
    """
    Swap ether for $LINK
    """
    pass


@internal
def _swap_link_out():
    """
    Swap $LINK for ether
    """
    pass


@external
def check_upkeep():
    """
    Loop over every member in the swarm and make sure their upkeeper's $LINK
    balance is sufficient
    """
    pass
