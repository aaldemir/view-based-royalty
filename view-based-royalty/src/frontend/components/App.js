import {
  BrowserRouter,
  Routes,
  Route
} from "react-router-dom";
import Navigation from './Navbar';
import Home from './Home.js'
import Create from './Create.js'
import NFTAbi from '../contractsData/PayPerView.json'
import NFTAddress from '../contractsData/PayPerView-address.json'
import { useState } from 'react'
import { ethers } from "ethers"
import { Spinner } from 'react-bootstrap'

import './App.css';

function App() {

  // goerli id is 5
  const SUPPORTED_CHAIN_IDS = [31337];

  const [loading, setLoading] = useState(true)
  const [account, setAccount] = useState(null)
  const [nft, setNFT] = useState({})
  // MetaMask Login/Connect
  const web3Handler = async () => {
    const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
    setAccount(accounts[0]);
    // Get provider from Metamask
    const provider = new ethers.providers.Web3Provider(window.ethereum);
    // Set signer
    const signer = provider.getSigner();

    window.ethereum.on('chainChanged', (chainId) => {
      if (!SUPPORTED_CHAIN_IDS.includes(chainId)) {
        alert(`Only compatible with chainIds ${SUPPORTED_CHAIN_IDS}`);
      }
      window.location.reload();
    })
    window.ethereum.on('accountsChanged', async function (accounts) {
      setAccount(accounts[0]);
      await web3Handler();
    })
    loadContracts(signer);
  }

  const loadContracts = async (signer) => {
    const nft = new ethers.Contract(NFTAddress.address, NFTAbi.abi, signer);
    setNFT(nft);
    setLoading(false);
  }

  return (
      <BrowserRouter>
        <div className="App">
          <>
            <Navigation web3Handler={web3Handler} account={account} />
          </>
          <div>
            {loading ? (
                <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '80vh' }}>
                  <Spinner animation="border" style={{ display: 'flex' }} />
                  <p className='mx-3 my-0'>Awaiting Metamask Connection...</p>
                </div>
            ) : (
                <Routes>
                  <Route path="/" element={
                    <Home nft={nft} account={account} />
                  } />
                  <Route path="/create" element={
                    <Create nft={nft} />
                  } />
                </Routes>
            )}
          </div>
        </div>
      </BrowserRouter>

  );
}

export default App;
