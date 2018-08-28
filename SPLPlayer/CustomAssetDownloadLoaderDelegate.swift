
//
//  CustomAssetDownloadLoaderDelegate.swift
//  SPLPlayer
//
//  Created by Sean Gray on 12/8/17.
//

import UIKit
import AVFoundation
import AVKit

class CustomAssetDownloadLoaderDelegate: CustomAssetLoaderDelegate {
    var assetID : String? = nil;
    
    func getKeySaveLocation(_ assetId:String) -> URL {
        let persistantPathString = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
        return URL(fileURLWithPath:persistantPathString!+"/"+assetId)
    }
    
    func returnLocalKey(request:AVAssetResourceLoadingRequest,context:Data) -> Bool {
        guard let contentInformationRequest = request.contentInformationRequest else {
            print("contentInformationError")
            return false
            
        }
        contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType
        request.dataRequest!.respond(with: context)
        request.finishLoading()
        return true;
    }
    
    override func removeKey(fileManager: FileManager){
            guard let assetID = self.assetID else { return }
            if fileManager.fileExists(atPath: getKeySaveLocation(assetID).path) {
        do {
                    try fileManager.removeItem(at: self.getKeySaveLocation(assetID))
                }
                catch {
                    print("Key removal Error \(error)")
        }
        }
    }
    override func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                                 shouldWaitForLoadingOfRequestedResource loadingRequest:AVAssetResourceLoadingRequest) -> Bool{
        let assetURI: NSURL = loadingRequest.request.url! as NSURL;
        self.assetID = assetURI.parameterString!;
        let scheme:String = assetURI.scheme!;
        if (!(scheme == "skd")){
            return false;
        }
        do {
            let persistentContentKeyContext = try Data(contentsOf:getKeySaveLocation(assetID!))
            return returnLocalKey(request:loadingRequest,context:persistentContentKeyContext)
        }
        catch {
            if !Reachability.isConnectedToNetwork() {
                return false;
            }
            var requestBytes:Data? = nil;
            var certificate: Data? = nil;
            NSLog("assetId:  %@", assetID!);
            do{
                certificate = try getAppCertificate(assetId: assetID!)
            }
            catch {
                loadingRequest.finishLoading(with: NSError(domain:NSURLErrorDomain,code:NSURLErrorClientCertificateRejected, userInfo:nil))
            }
            do{
                requestBytes = try loadingRequest.streamingContentKeyRequestData(
                    forApp: certificate!,
                    contentIdentifier: assetID!.data(using: String.Encoding.utf8)!,
                    options: [AVAssetResourceLoadingRequestStreamingContentKeyRequestRequiresPersistentKey: true])
            }
            catch{
                loadingRequest.finishLoading(with:error)
                return true;
            }
            
            let passthruParams: String = "?customdata=MTp3c2lsdmFAc2Nob29sb2ZuZXQuY29tOjc3Mjc6Y291cnNl";
            var responseData: Data? = nil;
            let error: Error? = nil;
            
            responseData = getContentKeyAndLeaseExpiryfromKeyServerModuleWithRequest(requestBytes: requestBytes!,
                                                                                     assetId: assetID!,
                                                                                     customParams: passthruParams,
                                                                                     errorOut: error)
            if ( responseData != nil){
                let dataRequest: AVAssetResourceLoadingDataRequest = loadingRequest.dataRequest!;
                do {
                    let persistantContentKeyContext = try loadingRequest.persistentContentKey(fromKeyVendorResponse: responseData!, options: nil)
                    try persistantContentKeyContext.write(to: getKeySaveLocation(assetID!), options: .atomic)
                    guard let contentInformationRequest = loadingRequest.contentInformationRequest else {
                        print("contentInformationError")
                        return false
                        
                    }
                    contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType
                    dataRequest.respond(with: persistantContentKeyContext)
                }
                catch {
                    
                    print("Error info: \(error)")
                    return false;
                }
                loadingRequest.finishLoading()
            }
            else{
                loadingRequest.finishLoading(with:error);
            }
            
            return true;
        }
    }
    
    override func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        print("shouldWaitForRenewalOfRequestedResource")
        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: renewalRequest)
    }

}
