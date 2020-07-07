//
//  ViewController.swift
//  MusicInstruments
//
//  Created by Martin Mitrevski on 12/9/19.
//  Copyright © 2019 Martin Mitrevski. All rights reserved.
//

import UIKit
import AVKit
import SoundAnalysis

class ViewController: UIViewController {
  
  private let audioEngine = AVAudioEngine()
  private var soundClassifier = IceSound()
  var streamAnalyzer: SNAudioStreamAnalyzer!
  let queue = DispatchQueue(label: "com.mitrevski.musicinstruments")
  var results = [(label: String, confidence: Float)]() {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.tableView.reloadData()
      }
    }
  }
  
  @IBOutlet weak var tableView: UITableView!
  
  
  override func viewWillDisappear(_ animated: Bool) {
    RadioPlayer.sharedInstance.pause()
  }
  
  override func viewDidAppear(_ animated: Bool) {
    RadioPlayer.sharedInstance.play()
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.title = "IceCreme caller"
    RadioPlayer.sharedInstance.errorDelegate = self
    RadioPlayer.sharedInstance.instanceDelegate = self
    do {
      let audioSession = AVAudioSession.sharedInstance()
      let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth, .allowAirPlay]
      try? audioSession.setCategory(AVAudioSession.Category.playAndRecord,
                                    mode: AVAudioSession.Mode.default, options: options)
    } catch let error as NSError {
      print(error.localizedDescription)
    }
  }
  
  private func startAudioEngine() {
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      showAudioError()
    }
  }
  
  private func prepareForRecording() {
    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    streamAnalyzer = SNAudioStreamAnalyzer(format: recordingFormat)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
      [unowned self] (buffer, when) in
      self.queue.async {
        self.streamAnalyzer.analyze(buffer,
                                    atAudioFramePosition: when.sampleTime)
      }
    }
    startAudioEngine()
  }
  
  private func createClassificationRequest() {
    do {
      let request = try SNClassifySoundRequest(mlModel: soundClassifier.model)
      try streamAnalyzer.add(request, withObserver: self)
    } catch {
      fatalError("error adding the classification request")
    }
  }
  
  @IBAction func startRecordingButtonTapped(_ sender: UIButton) {
    prepareForRecording()
    createClassificationRequest()
    UIApplication.shared.isIdleTimerDisabled = true
  }
  
}

extension ViewController: UITableViewDataSource {
  
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return results.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    var cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell")
    if cell == nil {
      cell = UITableViewCell(style: .default, reuseIdentifier: "ResultCell")
    }
    
    let result = results[indexPath.row]
    let label = convert(id: result.label)
    cell!.textLabel!.text = "\(label): \(result.confidence)"
    return cell!
  }
  
  private func convert(id: String) -> String {
    let mapping = ["all":"all","pass":"pass" ]
    return mapping[id] ?? id
  }
}

extension ViewController: SNResultsObserving {
  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let result = result as? SNClassificationResult else { return }
    var temp = [(label: String, confidence: Float)]()
    let sorted = result.classifications.sorted { (first, second) -> Bool in
      return first.confidence > second.confidence
    }
    for classification in sorted {
      let confidence = ceil( classification.confidence * 100 )
      if confidence > 5 {
        temp.append((label: classification.identifier, confidence: Float(confidence)))
      }
      
      if classification.identifier == "pass" && confidence > 90 {
        DispatchQueue.main.async { [weak self] in
          self?.makeCall()
        }
      }
    }
    results = temp
  }
}

extension ViewController {
  
  func showAlert(title: String, message: String) {
    let alert = UIAlertController(title: title,
                                  message: message,
                                  preferredStyle: .alert)
    let action = UIAlertAction(title: "OK", style: .default, handler: nil)
    alert.addAction(action)
    self.present(alert, animated: true, completion: nil)
  }
  
  func showAudioError() {
    let errorTitle = "Audio Error"
    let errorMessage = "Recording is not possible at the moment."
    self.showAlert(title: errorTitle, message: errorMessage)
  }
  
  
  func makeCall() {
    guard let number = URL(string: "tel://+380445372145") else { return }
    UIApplication.shared.open(number)
  }
}


extension ViewController: errorMessageDelegate, sharedInstanceDelegate {
  func errorMessageChanged(newVal: String) {
      print("Error changed to '\(newVal)'")
      RadioPlayer.sharedInstance.pause()
  }

  func sharedInstanceChanged(newVal: Bool) {
      print("Detected New Instance")
      if newVal {
          RadioPlayer.sharedInstance.play()
      }
  }
}
