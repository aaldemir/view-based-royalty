require('@nomiclabs/hardhat-waffle');
const secrets = require('./secrets.config');

module.exports = {
  solidity: '0.8.4',
  paths: {
    artifacts: './src/backend/artifacts',
    sources: './src/backend/contracts',
    cache: './src/backend/cache',
  },
  networks: {
    hardhat: {
      forking: {
        url: 'https://api.avax.network/ext/bc/C/rpc',
        // latest price will be 1669820789
        blockNumber: 16864986,
      },
    },
  },
};
