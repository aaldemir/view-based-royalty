// run 'npx hardhat node' in 1 terminal tab to fork network from archival node
// test with 'npx hardhat test'
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { getTokenURI } = require('./testUtils');

const TOKEN_NAME = 'PayPerView';
const TOKEN_SYMBOL = 'PPV';
const PRICE_FEED_AVAX_USD_MAIN = '0x0A77230d17318075983913bC2145DB16C7366156';
//const PRICE_FEED_USDC_USD_MAIN = '0xF096872672F44d6EBA71458D74fe67F9a77a23B9';

async function deploy() {
  const ViewBasedRoyalty = await ethers.getContractFactory('PayPerView');
  const ppv = await ViewBasedRoyalty.deploy(TOKEN_NAME, TOKEN_SYMBOL);
  await ppv.deployed();
  return ppv;
}

async function initializeWithPriceFeedAddress(
  contractInstance,
  deployerAddress,
  priceFeedAddress
) {
  await contractInstance.connect(deployerAddress).init(priceFeedAddress);
}

describe('PayPerView.sol', function () {
  let addr1, addr2, addr3;
  let ppv;

  before(async function () {
    ppv = await deploy();
    [addr1, addr2, addr3] = await ethers.getSigners();
    await initializeWithPriceFeedAddress(ppv, addr1, PRICE_FEED_AVAX_USD_MAIN);
  });

  it('should get name', async function () {
    expect(await ppv.name()).to.equal(TOKEN_NAME);
  });

  it('should get symbol', async function () {
    expect(await ppv.symbol()).to.equal(TOKEN_SYMBOL);
  });

  describe('function tests', function () {
    let tokenCount = 0;

    describe('mint', function () {
      it('should mint a token starting with id 1', async function () {
        tokenCount++;
        await ppv.connect(addr1).mint(getTokenURI(tokenCount));
        expect(await ppv.getTokenURI(tokenCount)).to.equal(
          getTokenURI(tokenCount)
        );
      });

      it('should mint a token with id incremented by 1', async function () {
        tokenCount++;
        const [addr2] = await ethers.getSigners();
        await ppv.connect(addr2).mint(getTokenURI(tokenCount));
        expect(await ppv.getTokenURI(tokenCount)).to.equal(
          getTokenURI(tokenCount)
        );
        tokenCount++;
        await ppv.connect(addr2).mint(getTokenURI(tokenCount));
        expect(await ppv.getTokenURI(tokenCount)).to.equal(
          getTokenURI(tokenCount)
        );
      });
    });

    describe('mintWithCustomParams', function () {
      it('should mint a token with specifications', async function () {
        tokenCount++;
        const duration = 60 * 60 * 24;
        const amountUSDPennies = 1000000;
        await ppv
          .connect(addr2)
          .mintWithCustomParams(
            getTokenURI(tokenCount),
            duration,
            amountUSDPennies,
            [addr2.address, addr3.address],
            [5000, 5000]
          );
        const viewingDetails = await ppv.viewingDetailsFor(tokenCount);
        expect(await ppv.getTokenURI(tokenCount)).to.equal(
          getTokenURI(tokenCount)
        );
        expect(viewingDetails.length).to.equal(2);
        expect(viewingDetails[0]).to.equal(duration);
        expect(viewingDetails[1]).to.equal(amountUSDPennies.toString());
        // check recipients
        const tokenIdsRedeemableAddr2 = await ppv
          .connect(addr2)
          .getTokenIdsAddressCanRedeemFrom();
        expect(tokenIdsRedeemableAddr2.length).to.equal(1);
        expect(tokenIdsRedeemableAddr2[0]).to.equal(tokenCount);
        const tokenIdsRedeemableAddr3 = await ppv
          .connect(addr3)
          .getTokenIdsAddressCanRedeemFrom();
        expect(tokenIdsRedeemableAddr3.length).to.equal(1);
        expect(tokenIdsRedeemableAddr3[0]).to.equal(tokenCount);
      });
    });

    describe('price feed tests', function () {
      it('getLatestPrice', async function () {
        const latestPrice = await ppv.getLatestPrice();
        // based on block 16864986
        expect(latestPrice).to.equal(ethers.BigNumber.from(1669820789));
      });

      it('convertDollarsToNanoAvax', async function () {
        const dollarsToExpectedPriceMap = {
          1: 59886666,
          1500: 898299991,
          1501: 898898858,
          99999900: 59886606190800,
          10101010101000: 6049158189630000000,
        };
        let convertedAmount;
        Object.keys(dollarsToExpectedPriceMap).forEach(async (cents) => {
          convertedAmount = await ppv.convertDollarsToNanoAvax(cents);
          expect(convertedAmount).to.equal(
            ethers.BigNumber.from(dollarsToExpectedPriceMap[cents])
          );
        });
      });
    });

    describe('addViewerWithStable', function () {});

    describe('addViewer', function () {
      // what happens if royaltyRecipientsByToken is not set for the _id

      it('should not add viewer if payment is not sufficient', async function () {});

      it('should not add viewer to a token that does not exist', async function () {});
    });

    describe('setRoyaltyRecipients', function () {});
  });

  // test mint

  // test can view

  // test add viewer

  // test viewing encrypted token URI, converting to string, decrypting

  // test redemption

  // test Chainlink Price oracle by forking mainnet
});
