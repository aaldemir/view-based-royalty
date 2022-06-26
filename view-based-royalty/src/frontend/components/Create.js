import { useState } from 'react'
import { Row, Form, Button } from 'react-bootstrap'
import { create as ipfsHttpClient } from 'ipfs-http-client'
const client = ipfsHttpClient('https://ipfs.infura.io:5001/api/v0')

const Create = ({ nft }) => {
    const [image, setImage] = useState('');
    const [price, setPrice] = useState('');
    const [duration, setDuration] = useState('');
    const [name, setName] = useState('');
    const [description, setDescription] = useState('');
    // comma separated
    const [recipients, setRecipients] = useState('');
    // comma separated
    const [allocations, setAllocations] = useState('');

    const uploadToIPFS = async (event) => {
        event.preventDefault()
        const file = event.target.files[0]
        if (typeof file !== 'undefined') {
            try {
                const result = await client.add(file)
                console.log(result)
                setImage(`https://ipfs.infura.io/ipfs/${result.path}`)
            } catch (error){
                console.log("ipfs image upload error: ", error)
            }
        }
    }

    const createNFT = async () => {
        if (!image || !name || !description) return
        try {
            const result = await client.add(JSON.stringify({image, price, name, description}));
            mintThenList(result);
        } catch(error) {
            console.log("ipfs uri upload error: ", error);
        }
    }

    const mintThenList = async (result) => {
        const uri = `https://ipfs.infura.io/ipfs/${result.path}`
        const recipientsArr = recipients.split(',');
        const allocationsArr = allocations.split(',').map(value => parseInt(value, 10));
        // mint nft
        if (price.length && duration.length) {
            await(await nft.mintWithCustomParams(uri, duration, price, recipientsArr, allocationsArr)).wait()
        } else {
            // use default price and duration params
            await(await nft.mintWithDefaultParams(uri, recipientsArr, allocationsArr)).wait()
        }
    }

    return (
        <div className="container-fluid mt-5">
            <div className="row">
                <main role="main" className="col-lg-12 mx-auto" style={{ maxWidth: '1000px' }}>
                    <div className="content mx-auto">
                        <Row className="g-4">
                            <Form.Control
                                type="file"
                                required
                                name="file"
                                onChange={uploadToIPFS}
                            />
                            <Form.Control onChange={(e) => setName(e.target.value)} size="lg" required type="text" placeholder="Name" />
                            <Form.Control onChange={(e) => setDescription(e.target.value)} size="lg" required as="textarea" placeholder="Description" />
                            <Form.Control onChange={(e) => setPrice(e.target.value)} size="lg" required type="number" placeholder="Price to view in ETH (default is 0.1 ETH)" />
                            <Form.Control onChange={(e) => setDuration(e.target.value)} size="lg" required type="number" placeholder="View duration in seconds (default is 1 week)" />
                            <Form.Control onChange={(e) => setRecipients(e.target.value)} size="lg" required type="text" placeholder="Addresses to receive royalty (comma separated)" />
                            <Form.Control onChange={(e) => setAllocations(e.target.value)} size="lg" required type="text" placeholder="Allocation in hundredths of a percent to each address in same order of addresses (comma separated)" />
                            <div className="d-grid px-0">
                                <Button onClick={createNFT} variant="primary" size="lg">
                                    Create & List NFT!
                                </Button>
                            </div>
                        </Row>
                    </div>
                </main>
            </div>
        </div>
    );
}

export default Create
