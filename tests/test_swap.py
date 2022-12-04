from brownie import reverts


def test_swap_link_in_from_deployer(deployer, link, kk):
    bal_ether = kk.balance()
    bal_link = link.balanceOf(kk)

    kk.swap_link_in(1e18, {"from": deployer, "value": 1e18})

    # confirm $link tokens were acquired
    assert link.balanceOf(kk) == bal_link + 1e18

    # 1 ether buys a lot more than 1 $link;
    # remainder should remain in the contract
    assert kk.balance() > bal_ether


def test_swap_link_in_from_eoa(random_eoa, link, kk):
    bal_ether = kk.balance()
    bal_link = link.balanceOf(kk)

    kk.swap_link_in(1e18, {"from": random_eoa, "value": 1e18})

    # confirm $link tokens were acquired
    assert link.balanceOf(kk) == bal_link + 1e18

    # 1 ether buys a lot more than 1 $link;
    # remainder should remain in the contract
    assert kk.balance() > bal_ether


def test_swap_link_in_not_funded(deployer, kk):
    # should revert if no ether is provided by caller,
    # even though there is enough ether available
    deployer.transfer(kk, 1e18)
    assert kk.balance() > 1e18
    with reverts("UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"):
        kk.swap_link_in(1e18, {"from": deployer, "value": 0})
