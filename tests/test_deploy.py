from brownie.convert import to_address


def test_deployed(kk):
    # naive way of checking if contract is up
    addr = kk.address
    assert to_address(addr) == addr


def test_owner(deployer, kk):
    # the deployer should be owner
    assert kk.owner() == deployer


def test_initialise_swarm(deployer, kk):
    # send 10 ether to enable buying $link needed for upkeep
    kk.initialise({"from": deployer, "value": 10e18})


def test_has_ether(kk):
    # not all ether was spent
    assert kk.balance() > 0


def test_has_no_link(kk, link):
    # amount of $link bought is exactly the same as what is sent to registrar
    assert link.balanceOf(kk) == 0


def test_swarm_initialised(kk):
    # we should have chainlink's upkeep id in the swarm
    assert kk.swarm(0) != 0
