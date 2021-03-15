//
//  VideoWriter.swift
//  AVCaptureVideoDataOutputSample_Concatenation
//
//  Created by hirauchi.shinichi on 2017/01/06.
//  Copyright © 2017年 SAPPOROWORKS. All rights reserved.
//

import UIKit
import AVFoundation


protocol VideoWriterDelegate {
    // 録画時間の更新
    func changeRecordingTime(s: Int64)
    // 録画終了
    func finishRecording(fileUrl: URL)
}

class VideoWriter : NSObject {
    
    var delegate: VideoWriterDelegate?
    
    //# 初期化でエラーが起こると`writer`がnilのインスタンスができると言う点は踏襲する
    fileprivate var writer: AVAssetWriter?
    //# 初期化時に必ず非nilの値が与えられるため、非Optionalとする
    fileprivate let videoInput: AVAssetWriterInput
    fileprivate let audioInput: AVAssetWriterInput
    
    //# Implicitly Unwrapped Optionalとするには危険なため初期値を与える
    fileprivate var lastTime: CMTime = .zero // 最後に保存したデータのPTS
    fileprivate var offsetTime = CMTime.zero // オフセットPTS(開始を0とする)

    fileprivate var recordingTime: Int64 = 0 // 録画時間
    
    fileprivate enum Status {
        case start // 初期化時
        case write // 書き込み中
        case pause // 一時停止
        case restart // 一時停止からの復帰
        case end // データ保存完了
    }
    
    fileprivate var status = Status.start
    
    init(height: Int,
         width: Int,
         channels: Int,
         samples: Float64,
         recordingTime: Int64
    ) {
        
        self.recordingTime = recordingTime
        
        // データ保存のパスを生成
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectoryUrl = urls[0]
        let fileUrl = documentsDirectoryUrl.appendingPathComponent("temp.mov")
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            do {
                try FileManager.default.removeItem(at: fileUrl)
            } catch {
                print(error)
            }
        }

        // AVAssetWriter生成
        do {
            writer = try AVAssetWriter(outputURL: fileUrl, fileType: .mov)
        } catch {
            print(error)
        }
        
        // Video入力
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey : AVVideoCodecType.h264.rawValue,
            AVVideoWidthKey : width,
            AVVideoHeightKey : height
        ];
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer?.add(videoInput)
        
        // Audio入力
        let audioOutputSettings: [String: Any] = [
            AVFormatIDKey : kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey : channels,
            AVSampleRateKey : samples,
            AVEncoderBitRateKey : 128000
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
        audioInput.expectsMediaDataInRealTime = true
        writer?.add(audioInput)
    }
    
    func recodingTime() -> CMTime {
        return CMTimeSubtract(lastTime, offsetTime)
    }
    
    func write(sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        
        if status == .start || status == .end || status == .pause {
            return
        }

        // 一時停止から復帰した場合は、一時停止中の時間をoffsetTimeに追加する
        if status == .restart {
            let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer) // 今取得したデータの時間
            let spanTime = CMTimeSubtract(timeStamp, lastTime) // 最後に取得したデータとの差で一時停止中の時間を計算する
            offsetTime = CMTimeAdd(offsetTime, spanTime) // 一時停止中の時間をoffsetTimeに追加する
            status = .write
        }
        
        if CMSampleBufferDataIsReady(sampleBuffer) {

            // 開始直後は音声データのみしか来ないので、最初の動画が来てから書き込みを開始する
            if isVideo && writer?.status == .unknown {
                offsetTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer) // 開始時間を0とするために、開始時間をoffSetに保存する
                writer?.startWriting()
                writer?.startSession(atSourceTime: .zero) // 開始時間を0で初期化する
            }
            
            if writer?.status == .writing {
                
                // PTSの調整（offSetTimeだけマイナスする）
                var copyBuffer : CMSampleBuffer?
                var count: CMItemCount = 1
                var info = CMSampleTimingInfo()
                CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &info, entriesNeededOut: &count)
                info.presentationTimeStamp = CMTimeSubtract(info.presentationTimeStamp, offsetTime)
                CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,sampleBuffer: sampleBuffer,sampleTimingEntryCount: 1,sampleTimingArray: &info,sampleBufferOut: &copyBuffer)
                
                lastTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer) // 最後のデータの時間を記録する
                if recodingTime() > CMTimeMake(value: Int64(recordingTime), timescale: 1) {
                    self.writer?.finishWriting(completionHandler: {
                        DispatchQueue.main.async {
                            self.delegate?.finishRecording(fileUrl: self.writer!.outputURL) // 録画終了
                        }
                    })
                    status = .end
                    return
                }

                if isVideo {
                    if videoInput.isReadyForMoreMediaData {
                        videoInput.append(copyBuffer!)
                    }
                } else {
                    if audioInput.isReadyForMoreMediaData {
                        audioInput.append(copyBuffer!)
                    }
                }
                delegate?.changeRecordingTime(s: recodingTime().value) // 録画時間の更新
            }
        }
    }
    
    func pause() {
        if status == .write {
            status = .pause
        }
    }
    
    func start() {
        if status == .start {
            status = .write
        } else if status == .pause {
            status = .restart // 一時停止中の時間をPauseTimeに追加するためのステータス
        }
    }
}

/*
 フレーム通りに動画データが入ってくると言う前提なら
 次のように開始時間を0にして、(counter,30)を追加していく方法もある
 writer?.startWriting()
 writer?.startSession(atSourceTime: kCMTimeZero)
 
 var info = CMSampleTimingInfo(duration: CMTimeMake(1,30), presentationTimeStamp: CMTimeMake(frameCounter,30), decodeTimeStamp: kCMTimeInvalid)
 var copyBuffer : CMSampleBuffer?
 CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,sampleBuffer,1,&info,&copyBuffer)
 
 writer endSessionAtSourceTime:CMTimeMake((int64_t)(frameCount - 1) * fps * durationForEachImage, fps)];
 */
