from brownie import reverts


def test_swap_link_in_from_owner(owner, link, kk):
    balance_ether = kk.balance()
    balance_link = link.balanceOf(kk)

    kk.swap_link_in(1e18, {"from": owner, "value": 1e18})

    # confirm $link tokens were acquired
    assert link.balanceOf(kk) == balance_link + 1e18

    # 1 ether buys a lot more than 1 $link;
    # remainder should remain in the contract
    assert kk.balance() > balance_ether


def test_swap_link_in_from_random_eoa(random_eoa, link, kk):
    balance_ether = kk.balance()
    balance_link = link.balanceOf(kk)

    kk.swap_link_in(1e18, {"from": random_eoa, "value": 1e18})

    # confirm $link tokens were acquired
    assert link.balanceOf(kk) == balance_link + 1e18

    # 1 ether buys a lot more than 1 $link;
    # remainder should remain in the contract
    assert kk.balance() > balance_ether


def test_swap_link_in_not_funded(deployer, kk):
    # should revert if no ether is provided by caller,
    # even though there is enough ether available
    deployer.transfer(kk, 1e18)
    assert kk.balance() >= 1e18
    with reverts("STF"):
        kk.swap_link_in(1e18, {"from": deployer, "value": 0})


def test_swap_link_out_from_owner(owner, link, kk):
    balance_ether = kk.balance()
    balance_link = link.balanceOf(kk)
    assert balance_link >= 1e18

    kk.swap_link_out(1e18, {"from": owner})

    # confirm ether was acquired
    assert kk.balance() > balance_ether

    # confirm $link tokens were divested
    assert link.balanceOf(kk) == balance_link - 1e18


def test_swap_link_out_from_random_eoa(random_eoa, kk):
    # should revert; only owner can call this
    with reverts():
        kk.swap_link_out(1e18, {"from": random_eoa, "value": 1e18})
