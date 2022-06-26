import { useState, useEffect } from 'react'
import { ethers } from 'ethers';
import { Row, Col, Card, Button } from 'react-bootstrap'
import logo from './eyes.png'

const Home = ({ account, nft }) => {
    const [loading, setLoading] = useState(true)
    const [items, setItems] = useState([])
    const loadItems = async () => {
        // Load all unsold items
        const itemCount = await nft.tokenCount();
        let items = []
        for (let i = 1; i <= itemCount; i++) {
            console.log(i);
            const canView = await nft.canView(account, i);
            // get uri url from nft contract
            const uri = await nft.getTokenURI(i);
            const tokenInfo = await nft.viewingDetailsFor(i);
            console.log(tokenInfo);
            // use uri to fetch the nft metadata stored on ipfs
            const response = await fetch(uri);
            const metadata = await response.json();
            // Add item to items array
            items.push({
                itemId: i,
                name: metadata.name,
                description: metadata.description,
                tokenURI: uri,
                amountToView: tokenInfo.amountToView,
                viewDuration: tokenInfo.viewDuration,
                canView,
                image: canView ? metadata.image : logo,
            });
        }
        setLoading(false)
        setItems(items)
    }

    const addViewer = async (item) => {
        await (await nft.addViewer(account, item.itemId, { value: item.amountToView })).wait();
        loadItems();
    }

    useEffect(() => {
        loadItems()
    }, [])

    if (loading) return (
        <main style={{ padding: "1rem 0" }}>
            <h2>Loading...</h2>
        </main>
    )

    return (
        <div className="flex justify-center">
            {items.length > 0 ?
                <div className="px-5 container">
                    <Row xs={1} md={2} lg={4} className="g-4 py-5">
                        {items.map((item, idx) => (
                            <Col key={idx} className="overflow-hidden">
                                <Card>
                                    <Card.Img variant="top" src={item.image} />
                                    <Card.Body color="secondary">
                                        <Card.Title>{item.name}</Card.Title>
                                        <Card.Text>
                                            {item.description}
                                        </Card.Text>
                                    </Card.Body>
                                    {!item.canView &&
                                        <Card.Footer>
                                            <div className='d-grid'>
                                                <Button onClick={() => addViewer(item)} variant="primary" size="lg">
                                                    {`Pay ${ethers.utils.formatUnits(item.amountToView, 'ether')} ETH to view item for ${item.viewDuration} seconds`}
                                                </Button>
                                            </div>
                                        </Card.Footer>
                                    }
                                </Card>
                            </Col>
                        ))}
                    </Row>
                </div>
                : (
                    <main style={{ padding: "1rem 0" }}>
                        <h2>No listed assets</h2>
                    </main>
                )}
        </div>
    );
}

export default Home;
