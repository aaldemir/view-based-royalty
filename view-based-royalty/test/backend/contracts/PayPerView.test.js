const { expect } = require('chai');
const { ethers } = require('hardhat');
const { getTokenURI } = require('./testUtils');

describe('PayPerView.sol', function () {
  let ppv;
  const TOKEN_NAME = 'PayPerView';
  const TOKEN_SYMBOL = 'PPV';
  before(async function () {
    const ViewBasedRoyalty = await ethers.getContractFactory('PayPerView');
    ppv = await ViewBasedRoyalty.deploy(TOKEN_NAME, TOKEN_SYMBOL);
    await ppv.deployed();
  });

  it('should get name', async function () {
    expect(await ppv.name()).to.equal(TOKEN_NAME);
  });

  it('should get symbol', async function () {
    expect(await ppv.symbol()).to.equal(TOKEN_SYMBOL);
  });

  describe('function tests', function () {
    let addr1, addr2, addr3;
    let tokenCount = 0;

    before(async function () {
      [addr1, addr2, addr3] = await ethers.getSigners();
    });

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
