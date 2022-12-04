import pytest
from brownie import Contract, KeeperKeeper, accounts


@pytest.fixture(scope="session")
def dev():
    return accounts[0]


@pytest.fixture(scope="session")
def kk(dev):
    return KeeperKeeper.deploy({"from": dev})


@pytest.fixture(scope="session")
def link():
    return Contract("0x514910771AF9Ca656af840dff83E8264EcF986CA")
