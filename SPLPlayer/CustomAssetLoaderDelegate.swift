//
//  CustomAssetLoaderDelegate.swift
//  SPLPlayer
//
//  Created by Sean Gray on 12/7/17.
//

import UIKit
import AVKit;
import AVFoundation;

class CustomAssetLoaderDelegate : NSObject, AVAssetResourceLoaderDelegate {
    
    enum error : Error {
        case missingApplicationCertificate
    }
    
    override init(){
        super.init()
    }
    
    func removeKey(fileManager: FileManager){
        
    }
    /*------------------------------------------
    **
    ** getContentKeyAndLeaseExpiryfromKeyServerModuleWithRequest
    **
    ** takes the bundled SPC and sends it the
    ** key server defined at KEY_SERVER_URL in the View Controller
    ** it returns a CKC which then is returned.
    ** ---------------------------------------*/
    func getContentKeyAndLeaseExpiryfromKeyServerModuleWithRequest(requestBytes: Data,
                                                                   assetId: String,
                                                                   customParams: String,
                                                                   errorOut: Error?) -> Data? {
        var decodedData: Data? = nil;
        var response: URLResponse? = nil
        let ksmURL: URL? = URL(string:KEY_SERVER_URL+assetId+customParams)
        
        let request = NSMutableURLRequest(url:ksmURL!);
        request.httpMethod = "POST";
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-type");
        request.httpBody = requestBytes;
        
        do {
            let dataVal = try NSURLConnection.sendSynchronousRequest(request as URLRequest, returning: &response)
            decodedData = dataVal
        }
        catch {
            print("SDK Error, SDK responded with Error: \(error)")
        }
        return decodedData
    }
    
    /*------------------------------------------
     **
     ** getAppCertificate
     **
     ** returns the apps certificate for authenticating against your server
     ** the example here uses a local certificate
     ** but you may need to edit this function to point to your certificate
     ** ---------------------------------------*/
    func getAppCertificate(assetId:String) throws -> Data? {
        var certificate: Data? = nil;
        
        let path = Bundle.main.path(forResource: "eleisure", ofType: "cer");
        
        let cert = URL(fileURLWithPath:path!);
        
        print (" Certificate URL " , separator:path! )
           print (" Certificate URL " , path! )
        try certificate = Data(contentsOf: cert);
        guard certificate != nil else {
            NSLog("certificate fail")
            return nil
        };
        return certificate!;
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,shouldWaitForLoadingOfRequestedResource loadingRequest:AVAssetResourceLoadingRequest) -> Bool{
        print(loadingRequest.request)
        let assetURI: NSURL = loadingRequest.request.url! as NSURL;
        let assetID:String = assetURI.parameterString!;
        let scheme:String = assetURI.scheme!;
        
        var requestBytes:Data? = nil;
        var certificate: Data? = nil;
        //skd is the scheme that the key requests use,makse sure that we are only doing key requests
        if (!(scheme == "skd")){
            return false;
        }
        
        do{
            certificate = try getAppCertificate(assetId: assetID)
        }
        catch {
            loadingRequest.finishLoading(with: NSError(domain:NSURLErrorDomain,code:NSURLErrorClientCertificateRejected, userInfo:nil))
        }
        do{
            requestBytes = try loadingRequest.streamingContentKeyRequestData(forApp: certificate!, contentIdentifier: assetID.data(using: String.Encoding.utf8)!, options: nil)
        }
        catch{
            loadingRequest.finishLoading(with:error)
            return true;
        }
        
        let passthruParams: String = "?customdata=MTp3c2lsdmFAc2Nob29sb2ZuZXQuY29tOjc3Mjc6Y291cnNl";
        var responseData: Data? = nil;
        let error: Error? = nil;
        
        responseData = getContentKeyAndLeaseExpiryfromKeyServerModuleWithRequest(requestBytes: requestBytes!,
                                                                                 assetId: assetID,
                                                                                 customParams: passthruParams,
                                                                                 errorOut: error)
        if ( responseData != nil){
            let dataRequest: AVAssetResourceLoadingDataRequest = loadingRequest.dataRequest!;
            dataRequest.respond(with: responseData!)
            loadingRequest.finishLoading()
        }
        else{
            loadingRequest.finishLoading(with:error);
        }
        
        return true;
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        print("shouldWaitForRenewalOfRequestedResource")
        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: renewalRequest)
    }
}
