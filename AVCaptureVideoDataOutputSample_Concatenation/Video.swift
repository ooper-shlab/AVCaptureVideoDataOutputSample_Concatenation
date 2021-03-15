//
//  Video.swift
//  AVCaptureVideoDataOutputSample_Concatenation
//
//  Created by hirauchi.shinichi on 2017/01/06.
//  Copyright © 2017年 SAPPOROWORKS. All rights reserved.
//

import AVFoundation
import UIKit


protocol VideoDelegate {
    // 録画時間の更新
    func changeRecordingTime(s: Int64)
    // 録画終了
    func finishRecording(fileUrl: URL, completionHandler: @escaping ()->Void)
}


class Video: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, VideoWriterDelegate {

    var delegate: VideoDelegate?
    fileprivate var recordingTime: Int64 = 0 // 録画時間(秒)
    
    fileprivate var videoWriter: VideoWriter?

    // HD (iPhone5S)
    let height: Int = 1280
    let width: Int = 789 //# なぜ789なのか不明、一応動くのでそのまま
    let sessionPreset = AVCaptureSession.Preset.hd1280x720
//    Full HD (iPhone6)
//    let height:Int = 1980
//    let width:Int = 1080
//    let sessionPreset = AVCaptureSessionPreset1980x1080
    
    private enum SetupError: Error {
        case noVideoDevice
        case noAudioDevice
        case noVideoConnection
    }

    //# 途中で失敗したら意味のない処理なので、throwsにする
    func setup(previewView: UIImageView, recordingTime: Int64) throws {
        
        self.recordingTime = recordingTime
        
        // セッションのインスタンス生成
        let captureSession = AVCaptureSession()
        
        // 入力（背面カメラ）
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            throw SetupError.noVideoDevice
        }
        videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30) // フレームレート １/30秒
        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        captureSession.addInput(videoInput)
        
        // 入力（マイク）
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw SetupError.noAudioDevice
        }
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        captureSession.addInput(audioInput);
        
        // 出力（映像）
        let videoDataOutput = AVCaptureVideoDataOutput()
        
        // ピクセルフォーマット(32bit BGRA)
        //videoDataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable : Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]
        // フレームをキャプチャするためのキューを指定
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        
        captureSession.addOutput(videoDataOutput)
        
        // カメラの方向をポートレートに固定する(AVCaptureSessionに追加後でないと処理できない)
        guard let videoConnection = videoDataOutput.connection(with: .video) else {
            throw SetupError.noVideoConnection
        }
        videoConnection.videoOrientation = .portrait
        
        // 出力(音声)
        let audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        captureSession.addOutput(audioDataOutput)
        
        // クオリティ
        captureSession.sessionPreset = sessionPreset
        
        // プレビュー
        let videoLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoLayer.frame = previewView.bounds
        videoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewView.layer.addSublayer(videoLayer)
        
        // セッションの開始
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }
    
    func start() -> Bool {
        if videoWriter != nil {
            videoWriter?.start()
            return true
        }
        return false
    }

    func pause() {
        videoWriter?.pause()
    }
    
    //# Swift 4以降ではシグニチャが変わっているので注意
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        let isVideo = captureOutput is AVCaptureVideoDataOutput
        if videoWriter == nil {
            if !isVideo {
                if let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt) {
                        let channels = Int(asbd.pointee.mChannelsPerFrame)
                        let samples = asbd.pointee.mSampleRate
                        videoWriter = VideoWriter(height: height, width: width, channels: channels, samples: samples, recordingTime: recordingTime)
                        videoWriter?.delegate = self
                    }
                }
            }
        }

        videoWriter?.write(sampleBuffer: sampleBuffer, isVideo: isVideo)
    }

    // 録画時間の更新
    func changeRecordingTime(s: Int64) {
        delegate?.changeRecordingTime(s: s)
    }
    
    // 録画終了
    func finishRecording(fileUrl: URL) {
        delegate?.finishRecording(fileUrl: fileUrl, completionHandler: {
            self.videoWriter = nil
        })
    }
}
