//
//  ViewController.swift
//  BoatTracker
//
//  Created by Benjamin on 22/04/2019.
//  Copyright © 2019 Courageous. All rights reserved.
//

import UIKit
import MapKit
import BarcodeScanner
import SwiftySuncalc
import OpenAPIClient

class ViewController: UIViewController, MKMapViewDelegate, BarcodeScannerCodeDelegate, BarcodeScannerDismissalDelegate, BarcodeScannerErrorDelegate, CLLocationManagerDelegate {
    
    @IBOutlet weak var checkInOutButton: UIButton!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var labelBoatName: UILabel!
    @IBOutlet weak var labelDistanceToHome: UILabel!
    @IBOutlet weak var labelDistance: UILabel!
    @IBOutlet weak var labelSunsetIn: UILabel!
    @IBOutlet weak var labelSunsetTime: UILabel!
    
    let kNoText = "-"
    
    var secret: UUID? = nil
    var baseLocation: CLLocation = CLLocation(latitude: 42.3721578, longitude: -71.0516434)
    
    let locationManager = CLLocationManager()
    var lastLocation: CLLocation? = nil
    let formatter: DateFormatter = DateFormatter()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        // API calls
        OpenAPIClientAPI.basePath = "TODO:put your back-end URL here"
        
        // Map setup
        mapView.delegate = self
        mapView.showsCompass = true
        mapView.region = MKCoordinateRegion(center: self.baseLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        addNOAAOverlay()
        
        // Location
        locationManager.delegate = self
        enableLocationServices()
        
        // UI labels
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        labelDistanceToHome.text = "DISTANCE_TO_HOME".localized()
        updateUi()
    }
    
    func addNOAAOverlay() {
        // From: https://nshipster.com/mktileoverlay-mkmapsnapshotter-mkdirections/
        let template = "https://tileservice.charts.noaa.gov/tiles/50000_1/{z}/{x}/{y}.png"
        
        let overlay = MKTileOverlay(urlTemplate: template)
        mapView.addOverlay(overlay, level: .aboveLabels)
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let tileOverlay = overlay as? MKTileOverlay else {
            return MKOverlayRenderer()
        }
        
        return MKTileOverlayRenderer(tileOverlay: tileOverlay)
    }
    
    @IBAction func onCheckInOut(_ sender: Any) {
        if (isCheckedOut()) {
            // Check-in (return) the boat
            let alert = UIAlertController(title: "CHECK_IN_CONFIRMATION_TITLE".localized(), message: "CHECK_IN_CONFIRMATION".localized(), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "NO".localized(), style: .cancel, handler: { _ in
                return
            }))
            alert.addAction(UIAlertAction(title: "YES".localized(), style: .default, handler: { _ in
                self.checkInBoat()
            }))
            self.present(alert, animated: true, completion: nil)
        } else {
            // Check-out the boat
            let viewController = BarcodeScannerViewController()
            viewController.codeDelegate = self
            viewController.dismissalDelegate = self
            viewController.errorDelegate = self
            
            present(viewController, animated: true, completion: nil)
        }
    }
    
    func scanner(_ controller: BarcodeScannerViewController, didCaptureCode code: String, type: String) {
        controller.dismiss(animated: true, completion: {
            print(code)
            self.checkOutBoat(secret: code)
        })
    }
    
    func scanner(_ controller: BarcodeScannerViewController, didReceiveError error: Error) {
        print(error)
        controller.dismiss(animated: true, completion: nil)
    }
    
    func scannerDidDismiss(_ controller: BarcodeScannerViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
    
    
    func enableLocationServices() {
        manageLocationStatus(manager: locationManager, status: CLLocationManager.authorizationStatus(), shouldAskPermission: true)
    }
    
    func startReceivingLocationChanges() {
        let authorizationStatus = CLLocationManager.authorizationStatus()
        if authorizationStatus != .authorizedWhenInUse && authorizationStatus != .authorizedAlways {
            // User has not authorized access to location information.
            return
        }
        // Do not start services that aren't available.
        if !CLLocationManager.locationServicesEnabled() {
            // Location services is not available.
            return
        }
        // Configure and start the service.
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10.0  // In meters.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = CLActivityType.otherNavigation
        locationManager.startUpdatingLocation()
    }
    
    func stopReceivingLocationChanges() {
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        manageLocationStatus(manager: manager, status: status, shouldAskPermission: false)
    }
    
    func manageLocationStatus(manager: CLLocationManager, status: CLAuthorizationStatus, shouldAskPermission: Bool) {
        
        switch status {
            
        case .restricted, .denied:
            // Disable your app's location features
            stopReceivingLocationChanges()
            break
            
        case .authorizedWhenInUse:
            if (shouldAskPermission) {
                // Request when-in-use authorization initially
                manager.requestAlwaysAuthorization()
            } else {
                // Enable only your app's when-in-use features.
                startReceivingLocationChanges()
            }
            break
            
        case .authorizedAlways:
            // Enable any of your app's location services.
            startReceivingLocationChanges()
            break
            
        case .notDetermined:
            if (shouldAskPermission) {
                // Request always authorization initially
                manager.requestAlwaysAuthorization()
            }
            break
            
        @unknown default:
            break
        }

    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last!
        self.lastLocation = loc
        
        // Do something with the location.
        self.mapView.centerCoordinate = loc.coordinate
        self.updateSunsetTime(location: loc)
        self.updateDistance(location: loc)
        self.reportLocation(location: loc)
    }
    
    func sunset(location: CLLocation) -> Date? {
        // Declare a new SwiftySuncalc object
        let suncalc: SwiftySuncalc! = SwiftySuncalc()
        
        // Find out the times for today (e.g. sunset or sunrise)
        let times = suncalc.getTimes(date: Date(), lat: location.coordinate.latitude, lng: location.coordinate.longitude);
        
        // Find out the time for sunset today
        return times["sunset"]
    }
    
    func checkOutBoat(secret: String) {
        guard let secretUuid = UUID.init(uuidString: secret) else { return }
        if (secretUuid == self.secret) {
            // Already check-out
            return
        }
        
        self.showCheckOutDialog() { name, phoneNumber in
            let assignationUpdate = AssignationUpdate(userName: name, userPhone: phoneNumber)
            UsersAPI.checkOut(secret: secretUuid, body: assignationUpdate) {data,error in
                if (error != nil) {
                    print("Unable to check-out")
                } else {
                    print("Check-out successful")
                    self.secret = secretUuid
                    self.updateUi()
                    self.enableLocationServices()
                }
            }
        }
    }
    
    func showCheckOutDialog(completion: @escaping ((_ name: String?, _ phoneNumber: String?) -> Void)) {
        // Largely from: https://www.simplifiedios.net/ios-dialog-box-with-input/
        
        // Get application preferences
        let preferences = UserDefaults.standard
        let kNameKey = "USER_NAME"
        let kPhoneKey = "USER_PHONE"
        
        // Creating UIAlertController and
        // Setting title and message for the alert dialog
        let alertController = UIAlertController(title: "CHECK_OUT".localized(), message: "CHECK_OUT_DETAILS_MESSAGE".localized(), preferredStyle: .alert)
        
        // The confirm action taking the inputs
        let confirmAction = UIAlertAction(title: "OK".localized(), style: .default) { (_) in
        
            // Getting the input values from user
            let name = alertController.textFields?[0].text
            let phoneNumber = alertController.textFields?[1].text
            
            // Save the preferences for faster check-out next time
            preferences.set(name, forKey: kNameKey)
            preferences.set(phoneNumber, forKey: kPhoneKey)

            completion(name, phoneNumber)
        }
        
        // The cancel action doing nothing
        let cancelAction = UIAlertAction(title: "CANCEL".localized(), style: .cancel) { (_) in }
        
        // Adding textfields to our dialog box
        alertController.addTextField { (textField) in
            textField.placeholder = "USER_NAME".localized()
            textField.text = preferences.string(forKey: kNameKey)
        }
        alertController.addTextField { (textField) in
            textField.placeholder = "PHONE_NUMBER".localized()
            textField.text = preferences.string(forKey: kPhoneKey)
        }
        
        // Adding the action to dialogbox
        alertController.addAction(confirmAction)
        alertController.addAction(cancelAction)
        
        // Finally presenting the dialog box
        self.present(alertController, animated: true, completion: nil)
    }
    
    func checkInBoat() {
        guard let secret = self.secret else { return }
        UsersAPI.checkIn(secret: secret) {data, error in
            if (error != nil) {
                if let err = error as? ErrorResponse {
                    switch(err){
                    case .error(404, _, _):
                        // Boat has been checked-in, go on with the process
                        self.stopReceivingLocationChanges()
                        self.secret = nil
                        self.updateUi()
                        break
                    case .error(_, _, _):
                        print("Unable to check-in")
                    }
                }
            } else {
                self.stopReceivingLocationChanges()
                self.secret = nil
                self.updateUi()
            }
        }
    }
    
    func reportLocation(location: CLLocation?) {
        if (location == nil || self.secret == nil) {
            return
        }
        
        let locationUpdate = LocationUpdate(latitude: location!.coordinate.latitude, longitude: location!.coordinate.longitude)
        UsersAPI.trackLocation(secret: self.secret!, body: locationUpdate) { data, error in
            if (error != nil) {
                if let err = error as? ErrorResponse {
                    switch(err){
                    case .error(403, _, _):
                        // Boat has been checked-in
                        self.checkInBoat()
                        break
                    case .error(_, _, _):
                        print("Unable to report location")
                    }
                }
            }
        }
    }
    
    func isCheckedOut() -> Bool {
        return self.secret != nil
    }
    
    func updateUi() {
        let resName = (isCheckedOut()) ? "CHECK_IN" : "CHECK_OUT"
        checkInOutButton.setTitle(resName.localized(), for: .normal)
        
        self.updateBoatName()
        self.updateDistance(location: self.lastLocation)
        self.updateSunsetTime(location: self.lastLocation)
    }
    
    func updateBoatName() {
        if (isCheckedOut() && self.secret != nil) {
            UsersAPI.assignedItem(secret: self.secret!) {data,error in
             if (error != nil || data == nil) {
                print("Unable to retrieve boat name")
             } else {
                self.labelBoatName.text = data?.name
             }
            }
        } else {
            self.labelBoatName.text = kNoText
        }
    }
    
    func updateDistance(location: CLLocation?) {
        if (location == nil) {
            labelDistance.text = kNoText
        } else {
            let distanceInM = location!.distance(from: self.baseLocation)
            let distanceInNMI = Measurement(value: distanceInM, unit: UnitLength.meters).converted(to: UnitLength.nauticalMiles)
            labelDistance.text = MeasurementFormatter().string(from: distanceInNMI)
        }
    }
    
    func updateSunsetTime(location: CLLocation?) {
        if (location == nil) {
            labelSunsetIn.text = ""
            labelSunsetTime.text = kNoText
        } else {
            let sunsetTime = sunset(location: lastLocation!)
            if (sunsetTime != nil) {
                let interval = sunsetTime!.timeIntervalSinceNow
                labelSunsetTime.text = formatter.string(from: sunsetTime!)
                let sunsetLabel = "SUNSET_IN".localized()
                let intervalStr = interval.format(using: [.hour, .minute])
                labelSunsetIn.text = String(format: sunsetLabel, arguments:  [intervalStr!])
            } else {
                labelSunsetIn.text = ""
                labelSunsetTime.text = kNoText
            }
        }
    }

}

extension TimeInterval {
    func format(using units: NSCalendar.Unit) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        
        return formatter.string(from: self)
    }
}

extension String {
    func localized(withComment:String="") -> String {
        return NSLocalizedString(self, tableName: nil, bundle: Bundle.main, value: "", comment: withComment)
    }
}
