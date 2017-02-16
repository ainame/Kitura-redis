/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import SwiftRedis
import Dispatch

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

import Foundation
import XCTest


public class TestPubSub: XCTestCase {
    static var allTests: [(String, (TestPubSub) -> () throws -> Void)] {
        return [
            ("test_1", test_1),
            ("test_2", test_2),
            ("test_3", test_3),
            ("test_4", test_4),
            ("test_5", test_5)
        ]
    }
    
    let secondConnection = Redis()
    
    let queue = DispatchQueue(label: "unblocker", attributes: DispatchQueue.Attributes.concurrent)
    
    var channel1: String { return "channel1" }
    var channel2: String { return "channel2" }
    var channel3: String { return "channel3" }
    
    var pattern1: String { return "c?annel1" }
    var pattern2: String { return "*2" }
    var pattern3: String { return "c[ha]annel3" }
    
    var messageA: String { return "A" }
    var messageB: String { return "B" }
    var messageC: String { return "C" }
    
    func localSetup(block: () -> Void) {
        connectRedis() { (error: NSError?) in
            if error != nil {
                XCTFail("Could not connect to Redis")
                return
            }
            
            redis.del(channel1, channel2, channel3,
                      pattern1, pattern2, pattern3,
                      messageA, messageB, messageC)
            { (deleted: Int?, error: NSError?) in
                block()
            }
        }
    }
    
    func extendedSetup(block: () -> Void) {
        localSetup() {
            let password = read(fileName: "password.txt")
            let host = read(fileName: "host.txt")
            
            secondConnection.connect(host: host, port: 6379) { (error: NSError?) in
                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                
                secondConnection.auth(password) { (error: NSError?) in
                    XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                    
                    block()
                }
            }
        }
    }
    
    // PUBLISH, SUBSCRIBE, UNSUBSCRIBE
    func test_1() {
        extendedSetup() {
            
            // Publish to channel1
            redis.publish(channel: channel1, message: messageA, callback: { (result, error) in
                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                
                // Subscribe to channel1
                secondConnection.subscribe(channels: channel1, callback: {
                    
                    // Publish to channel1
                    redis.publish(channel: channel1, message: messageA, callback: { (result, error) in
                        XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                        XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                        XCTAssertEqual(result, 1, "PUBLISH should return 1, not \(result).")
                        
                        // Unsubscribe to channel1
                        secondConnection.unsubscribe(channels: channel1, callback: { 
                            
                            // Publish to channel1
                            redis.publish(channel: channel1, message: messageA, callback: { (result, error) in
                                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                                XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                            })
                        })
                    })
                })
            })
        }
    }
    
    // PUBLISH, SUBSCRIBE, UNSUBSCRIBE multiple channels
    func test_2() {
        extendedSetup() {
            
            // Subscribe to channel1, channel2, channel3
            secondConnection.subscribe(channels: channel1, channel2, channel3, callback: {
                
                // Publish to channel1
                redis.publish(channel: channel1, message: messageA, callback: { (result, error) in
                    XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                    XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                    XCTAssertEqual(result, 1, "PUBLISH should return 1, not \(result).")
                    
                    // Publish to channel2
                    redis.publish(channel: channel2, message: messageA, callback: { (result, error) in
                        XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                        XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                        XCTAssertEqual(result, 1, "PUBLISH should return 1, not \(result).")
                        
                        // Unsubscribe from channel2, channel3
                        secondConnection.unsubscribe(channels: channel2, channel3, callback: {
                            
                            // Publish to channel2
                            redis.publish(channel: channel2, message: messageA, callback: { (result, error) in
                                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                                XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                            })
                            
                            // Publish to channel3
                            redis.publish(channel: channel3, message: messageA, callback: { (result, error) in
                                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                                XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                            })
                            
                            // Unsubscribe from all channels
                            secondConnection.unsubscribe(callback: {
                                
                                // Publish to channel1
                                redis.publish(channel: channel1, message: messageA, callback: { (result, error) in
                                    XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                    XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                                    XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                                })
                            })
                        })
                    })
                })
            })
        }
    }
    
    // PSUBSCRIBE, PUNSUBSCRIBE
    func test_3() {
        extendedSetup() {
            
            // Subscribe to pattern1, pattern2, pattern3
            secondConnection.psubscribe(patterns: pattern1, pattern2, pattern3, callback: {
                
                // Publish to pattern1
                redis.publish(channel: pattern1, message: messageA, callback: { (result, error) in
                    XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                    XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                    XCTAssertEqual(result, 1, "PUBLISH should return 1, not \(result).")
                    
                    // Publish to pattern2
                    redis.publish(channel: pattern2, message: messageA, callback: { (result, error) in
                        XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                        XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                        XCTAssertEqual(result, 1, "PUBLISH should return 1, not \(result).")
                        
                        // Unsubscribe from pattern2, pattern3
                        secondConnection.punsubscribe(patterns: pattern2, pattern3, callback: {
                            
                            // Publish to pattern2
                            redis.publish(channel: pattern2, message: messageA, callback: { (result, error) in
                                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                                XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                            })
                            
                            // Publish to pattern3
                            redis.publish(channel: pattern3, message: messageA, callback: { (result, error) in
                                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                                XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                            })
                            
                            // Unsubscribe from all channels
                            secondConnection.punsubscribe(callback: {
                                
                                // Publish to pattern1
                                redis.publish(channel: pattern1, message: messageA, callback: { (result, error) in
                                    XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                    XCTAssertNotNil(result, "PUBLISH should not have returned nil.")
                                    XCTAssertEqual(result, 0, "PUBLISH should return 0, not \(result).")
                                })
                            })
                        })
                    })
                })
            })
        }
    }
    
    // PUBSUB: CHANNELS, NUMSUB
    func test_4() {
        extendedSetup() {
            
            // NUMSUB with no channels
            redis.pubsubNumsub(callback: { (result, error) in
                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                XCTAssertNotNil(result, "PUBSUB CHANNELS should not have returned nil.")
                XCTAssertEqual(result?.count, 0, "PUBSUB NUMSUB result.COUNT should be 0, not \(result?.count).")
            })
         
            // Subscribe to channel1
            secondConnection.subscribe(channels: channel1, channel2, callback: {
                
                // PSUBSCRIBE to pattern2
                secondConnection.psubscribe(patterns: pattern3, callback: {
                    
                    // NUMSUB channel1, channel3
                    redis.pubsubNumsub(channels: channel1, channel3, callback: { (result, error) in
                        XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                        XCTAssertNotNil(result, "PUBSUB NUMSUB should not have returned nil.")
                        
                        let count = result?.count
                        XCTAssertEqual(count, 4, "PUBSUB NUMSUB result.count should be 4, not \(count)")
                        
                        let result0 = result?[0]?.asString
                        let result1 = result?[1]?.asInteger
                        let result2 = result?[2]?.asString
                        let result3 = result?[3]?.asInteger
                        XCTAssertEqual(result0, channel1, "PUBSUB NUMSUB result[0] should be \(channel1), not \(result0)")
                        XCTAssertEqual(result1, 1, "PUBSUB NUMSUB result[1] should be 1, not \(result1)")
                        XCTAssertEqual(result2, channel3, "PUBSUB NUMSUB result[2] should be \(channel3), not \(result2)")
                        XCTAssertEqual(result3, 0, "PUBSUB NUMSUB result[3] should be 0, not \(result3)")
                    })
                    
                    // CHANNELS on pattern1
                    redis.pubsubChannels(pattern: pattern1, callback: { (result, error) in
                        XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                        XCTAssertNotNil(result, "PUBSUB CHANNELS should not have returned nil.")
                        XCTAssertEqual(result?[0]?.asString, channel1, "PUBSUB CHANNELS result[0] should be 'channel1', not \(result).")
                    })

                    // CHANNELS get all
                    redis.pubsubChannels(callback: { (result, error) in
                        XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                        XCTAssertNotNil(result, "PUBSUB CHANNELS should not have returned nil.")
                        XCTAssertEqual(result?.count, 2, "PUBSUB CHANNELS result array should be size 2, not \(result).")
                    })
                })
            })
        }
    }
    
    // PUBSUB NUMPAT
    func test_5() {
        extendedSetup() {
            
            // NUMPAT
            redis.pubsubNumpat(callback: { (result, error) in
                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                XCTAssertNotNil(result, "PUBSUB NUMPAT should not have returned nil.")
                XCTAssertEqual(result, 0, "PUBSUB NUMPAT should reutnr 0, not \(result).")
                
                // SUBSCRIBE to channel1
                secondConnection.subscribe(channels: channel1, callback: { 
                    
                    // NUMPAT
                    redis.pubsubNumpat(callback: { (result, error) in
                        XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                        XCTAssertNotNil(result, "PUBSUB NUMPAT should not have returned nil.")
                        XCTAssertEqual(result, 0, "PUBSUB NUMPAT should reutnr 0, not \(result).")
                        
                        // PSUBSCRIBE to pattern1
                        secondConnection.psubscribe(patterns: pattern1, callback: { 
                            
                            // NUMPAT
                            redis.pubsubNumpat(callback: { (result, error) in
                                XCTAssertNil(error, "\(error != nil ? error!.localizedDescription : "")")
                                XCTAssertNotNil(result, "PUBSUB NUMPAT should not have returned nil.")
                                XCTAssertEqual(result, 1, "PUBSUB NUMPAT should reutnr 0, not \(result).")
                            })
                        })
                    })
                })
            })
        }
    }
}
