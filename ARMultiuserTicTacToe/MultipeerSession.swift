/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A simple abstraction of the MultipeerConnectivity API as used in this app.
*/

import MultipeerConnectivity

protocol MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peer: MCPeerID) -> Void
    func peerDiscovered(_ peer: MCPeerID) -> Bool
    func peerJoined(_ peer: MCPeerID) -> Void
    func peerLeft(_ peer: MCPeerID) -> Void
}

/// - Tag: MultipeerSession
class MultipeerSession: NSObject {
    static let serviceType = "ar-collab"
    
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var serviceAdvertiser: MCNearbyServiceAdvertiser!
    private var serviceBrowser: MCNearbyServiceBrowser!
    
    private var delegate: MultipeerSessionDelegate

    /// - Tag: MultipeerSetup
    init(delegate: MultipeerSessionDelegate) {
        self.delegate = delegate
        
        super.init()
        
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: MultipeerSession.serviceType)
        serviceAdvertiser.delegate = self
        serviceAdvertiser.startAdvertisingPeer()
        
        serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: MultipeerSession.serviceType)
        serviceBrowser.delegate = self
        serviceBrowser.startBrowsingForPeers()
    }
    
    deinit {
        serviceAdvertiser.stopAdvertisingPeer()
        serviceBrowser.stopBrowsingForPeers()
        session.disconnect()
        
        serviceAdvertiser = nil
        serviceBrowser = nil
        session = nil
    }
    
    func sendToAllPeers(_ data: Data, reliably: Bool) {
        sendToPeers(data, reliably: reliably, peers: connectedPeers)
    }
    
    /// - Tag: SendToPeers
    func sendToPeers(_ data: Data, reliably: Bool, peers: [MCPeerID]) {
        guard !peers.isEmpty else { return }
        do {
            try session.send(data, toPeers: peers, with: reliably ? .reliable : .unreliable)
        } catch {
            print("error sending data to peers \(peers): \(error.localizedDescription)")
        }
    }
    
    var connectedPeers: [MCPeerID] {
        return session.connectedPeers
    }
}

extension MultipeerSession: MCSessionDelegate {
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .connected {
            delegate.peerJoined(peerID)
        } else if state == .notConnected {
            delegate.peerLeft(peerID)
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        delegate.receivedData(data, from: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                 fromPeer peerID: MCPeerID) {
        fatalError("This service does not send/receive streams.")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        fatalError("This service does not send/receive resources.")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        fatalError("This service does not send/receive resources.")
    }
    
}

extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    
    /// - Tag: FoundPeer
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Ask the handler whether we should invite this peer or not
        let accepted = delegate.peerDiscovered(peerID)
        if accepted {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // This app doesn't do anything with non-invited peers, so there's nothing to do here.
    }
    
}

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    
    /// - Tag: AcceptInvite
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Call the handler to accept the peer's invitation to join.
        invitationHandler(true, self.session)
    }
}
