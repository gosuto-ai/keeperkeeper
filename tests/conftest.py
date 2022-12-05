import pytest
from brownie import Contract, KeeperKeeper, accounts


@pytest.fixture(scope="session")
def deployer():
    return accounts[0]


@pytest.fixture(scope="session")
def owner(deployer):
    return deployer


@pytest.fixture(scope="session")
def kk(deployer):
    return KeeperKeeper.deploy(deployer, {"from": deployer})


@pytest.fixture(scope="session")
def link():
    return Contract("0x514910771AF9Ca656af840dff83E8264EcF986CA")


@pytest.fixture(scope="function")
def random_eoa():
    # generate random account
    eoa = accounts.add()
    # fund with 10 ether
    accounts[1].transfer(eoa, 10e18)
    return eoa
