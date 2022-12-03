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
    # https://github.com/ethereum/EIPs/issues/677
    def balanceOf(_owner: address) -> uint256: view
    def transferAndCall(
        _to: address, _value: uint256, _data: Bytes[388]
    ) -> bool: nonpayable

interface IAutomationRegistry:
    # @chainlink/v0.8/interfaces/AutomationRegistryInterface1_3.sol
    def getState() -> (State, Config, address[1]): view

interface IKeeperRegistrar:
    # @chainlink/v0.8/KeeperRegistrar.sol
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
    def getRegistrationConfig() -> (
        AutoApproveType, uint32, uint32, address, uint256
    ): view

interface IEACAggregatorProxy:
    # @chainlink/v0.6/EACAggregatorProxy.sol
    def latestRoundData() -> (uint80, int256, uint256, uint256, uint80): view


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


# enums
enum AutoApproveType:  # IKeeperRegistrar
    DISABLED
    ENABLED_SENDER_ALLOWLIST
    ENABLED_ALL


# events
event LinkSwappedIn:
    amount: uint256

event LinkSwappedOut:
    amount: uint256


# constants
MAX_BPS: constant(uint256) = 1_000_000_000
MAX_SWARM_SIZE: constant(uint8) = 16
SELF_UPKEEP_GAS: constant(uint32) = 1_000_000  # TODO: replace, still an estimation

LINK: constant(address) = 0x514910771AF9Ca656af840dff83E8264EcF986CA
CL_REGISTRY: constant(address) = 0x02777053d6764996e594c3E88AF1D58D5363a2e6
CL_REGISTRAR: constant(address) = 0xDb8e8e2ccb5C033938736aa89Fe4fa1eDfD15a1d
UNIV3_ROUTER: constant(address) = 0xE592427A0AEce92De3Edee1F18E0157C05861564
FASTGAS_ORACLE: constant(address) = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C
LINKETH_ORACLE: constant(address) = 0xDC530D9457755926550b59e8ECcdaE7624181557


# storage vars
swarm: public(uint32[MAX_SWARM_SIZE])
premium: public(uint32)
gas_factor: public(uint16)
max_gas: public(uint32)
min_link: public(uint256)


@payable
@external
def __init__():
    """
    @notice Populate storage with relevant variables from registry and
            registrar's configs
    """
    self._refresh_registry_config_and_get_nonce()
    self._refresh_registrar_config()


@internal
def _register_self():
    """
    @notice Register self as the first member of the swarm; we depend on it
            for having our performUpkeep called
    """
    # add upkeep entry in chainlink's registry and get id back
    upkeep_id: uint32 = self._register_member(self, "KeeperKeeper", SELF_UPKEEP_GAS)

    # add new upkeep id to our swarm
    self.swarm[0] = upkeep_id


@internal
def _refresh_registry_config_and_get_nonce() -> uint32:
    """
    @notice Retrieve current state of the registry and save its relevant
            variables to storage
    @return The registry's current nonce
    """
    state: State = empty(State)
    config: Config = empty(Config)
    _a: address[1] = empty(address[1])
    state, config, _a = IAutomationRegistry(CL_REGISTRY).getState()

    self.premium = config.paymentPremiumPPB
    self.gas_factor = config.gasCeilingMultiplier
    self.max_gas = config.maxPerformGas

    return state.nonce


@internal
def _refresh_registrar_config():
    """
    @notice Get minimum amount of $LINK registrar requires in order to
            register an upkeep. Save value to storage
    @dev See variable minLINKJuels in @chainlink/v0.8/KeeperRegistrar.sol
    """
    self.min_link = IKeeperRegistrar(
        0xDb8e8e2ccb5C033938736aa89Fe4fa1eDfD15a1d
    ).getRegistrationConfig()[4]



@internal
def _register_member(member: address, name: String[64], gas_limit: uint32) -> uint32:
    """
    @notice Register an upkeep on the automation registrar and predict its id
    @dev https://docs.chain.link/chainlink-automation/register-upkeep/
    @param member Address of the member to register in the swarm
    @param name Name of the upkeep
    @param gas_limit Max gas that the member's performUpkeep will need
    @return The id of the newly registered upkeep
    """
    # buy more $link if there is not enough for initial funding of the upkeep
    if not self._enough_link(convert(gas_limit, int256)):
        self._swap_link_in()

    # get old nonce from registry to compare against new nonce later
    state: State = IAutomationRegistry(CL_REGISTRY).getState()[0]
    old_nonce: uint32 = state.nonce

    # confirm gas costs for member's performUpkeep are not too high
    assert gas_limit <= self.max_gas

    # calc amount of $link needed to fund upkeep
    link_threshold: uint256 = self._link_threshold(convert(gas_limit, int256))

    # build registration payload and send to registrar via erc677
    payload: Bytes[388] = _abi_encode(
        name,
        empty(bytes32),
        self,
        gas_limit,
        self,
        empty(bytes32),
        link_threshold,
        empty(uint256),
        self,
        method_id=0x3659d666
    )
    IERC677(LINK).transferAndCall(CL_REGISTRAR, link_threshold, payload)

    # get new nonce from registry and refresh its config in our storage
    new_nonce: uint32 = self._refresh_registry_config_and_get_nonce()
    if not new_nonce == old_nonce + 1:
        raise  # upkeep was not successfully registered!

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
def _enough_link(gas_per_upkeep: int256) -> bool:
    """"
    @notice Check if KeeperKeeper's $LINK's balance is high enough to register
            an upkeep with given gas value
    @param gas_per_upkeep Amount of gas a single call to performUpkeep costs
    @return True if there is enough balance, False if not
    """
    if IERC677(LINK).balanceOf(self) >= self._link_threshold(gas_per_upkeep):
        return True
    return False


@view
@internal
def _link_threshold(gas_per_upkeep: int256, n: int256 = 10) -> uint256:
    """
    @notice Minimal $LINK balance needed for a single swarm member to perform
            at least n upkeeps
    @dev https://docs.chain.link/chainlink-automation/automation-economics/
    @param gas_per_upkeep Amount of gas a single call to performUpkeep costs
    @param n Amount of times the performUpkeep should be able to be called
             before needing a topup
    @return Amount of $LINK in wei needed for n upkeeps in wei
    """
    max_bps: int256 = convert(MAX_BPS, int256)
    premium: int256 = convert(self.premium, int256)
    gas_price: int256 = IEACAggregatorProxy(FASTGAS_ORACLE).latestRoundData()[1]
    link_rate: int256 = IEACAggregatorProxy(LINKETH_ORACLE).latestRoundData()[1]

    ether_per_upkeep: int256 = gas_per_upkeep * gas_price
    incl_premium: int256 = ether_per_upkeep * (max_bps + premium) / max_bps
    incl_overhead: int256 = incl_premium + (80_000 * gas_price)
    link_threshold_in_wei: int256 = incl_overhead * 10 ** 18 / link_rate

    # assure upkeep can be performed n times
    link_threshold_in_wei *= n

    # make sure int256 is positive
    assert link_threshold_in_wei > 0

    # in either case make sure we use at least min_link as enforced by registrar
    return max(convert(link_threshold_in_wei, uint256), self.min_link)


@payable
@internal
def _swap_link_in():
    """
    @notice Swap ether for $LINK
    """
    pass


@internal
def _swap_link_out():
    """
    @notice Swap $LINK for ether
    """
    pass


@external
def check_upkeep():
    """
    @notice Loop over every member in the swarm and make sure their upkeeper's
            $LINK balance is sufficient
    """
    pass
