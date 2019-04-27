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
        labelDistanceToHome.text = NSLocalizedString("DISTANCE_TO_HOME", comment: "")
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
        let viewController = BarcodeScannerViewController()
        viewController.codeDelegate = self
        viewController.dismissalDelegate = self
        viewController.errorDelegate = self
        
        present(viewController, animated: true, completion: nil)
    }
    
    func scanner(_ controller: BarcodeScannerViewController, didCaptureCode code: String, type: String) {
        controller.dismiss(animated: true, completion: nil)

        print(code)
        checkOutBoat(secret: code)
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
            // Enable only your app's when-in-use features.
            startReceivingLocationChanges()
            break
            
        case .authorizedAlways:
            // Enable any of your app's location services.
            startReceivingLocationChanges()
            break
            
        case .notDetermined:
            if (shouldAskPermission) {
                // Request when-in-use authorization initially
                manager.requestWhenInUseAuthorization()
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

        let assignationUpdate = AssignationUpdate(userName: "Test", userPhone: "1234567890")
        UsersAPI.checkOut(secret: secretUuid, body: assignationUpdate) {data,error in
            if (error != nil) {
                print("Unable to check-out")
            } else {
                print("Check-out successful")
                self.secret = secretUuid
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
                print("Unable to report location")
            }
        }
    }
    
    func updateUi() {
        self.updateBoatName()
        self.updateDistance(location: self.lastLocation)
        self.updateSunsetTime(location: self.lastLocation)
    }
    
    func updateBoatName() {
        if (self.secret != nil) {
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
                let sunsetLabel = NSLocalizedString("SUNSET_IN", comment: "")
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
