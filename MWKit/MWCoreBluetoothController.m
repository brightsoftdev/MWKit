//
//  MWCoreBluetoothController.m
//  MWKit
//
//  Created by Kai Aras on 6/9/12.
//  Copyright (c) 2012 010dev. All rights reserved.
//

#import "MWCoreBluetoothController.h"
#import "MWMetaWatch.h"


@interface MWCoreBluetoothController ()
CBCentralManager *_manager;
CBPeripheral *_device;
CBService *_service;
CBDescriptor *_descriptor;

-(void)_startDiscovery;
@end

@implementation MWCoreBluetoothController

static MWCoreBluetoothController *sharedController;

#define kMWServiceUUID @"8880"
#define kMWWatchCharacteristicUUID @"8881"

#pragma mark - Singleton

+(MWCoreBluetoothController *) sharedController {
    if (sharedController == nil) {
        sharedController = [[super allocWithZone:NULL]init];
    }
    return sharedController;
    
}


- (id)init
{
    self = [super init];
    if (self) {
        _manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
        
    }
    return self;
}

-(void)dealloc {
    
    [_manager release];
    [_device release];
    [_service release];
    
    [super dealloc];
}

#pragma mark MWConnectionControllerDelegate

-(void)startDiscovery {
    
    if (_device) {
        [self closeChannel];
        [self performSelector:@selector(_startDiscovery) withObject:nil afterDelay:2.0];
        return;
    }
    
    [self _startDiscovery];
}

-(void)_startDiscovery {
    NSLog(@"%@ did Start Discovery",self);
    NSDictionary * options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:FALSE], CBCentralManagerScanOptionAllowDuplicatesKey, nil];
    
    [_manager scanForPeripheralsWithServices:[NSArray arrayWithObject:[CBUUID UUIDWithString:kMWServiceUUID]] options:options];

}

-(void)openChannel {
    // FIXME: implement direct connections
}


-(void)closeChannel {
    if ([_device isConnected]) {
        [_manager cancelPeripheralConnection:_device];
    }
}

-(void)sendFrame:(NSData *)frame withLenght:(unsigned char)lenght {
    
}


-(void)tx:(unsigned char)cmd options:(unsigned char)options data:(unsigned char *)inputData len:(unsigned char)len {
    unsigned short crc;
    unsigned char data[len+6]; 
    
    memset(data, 0, len+6);
    data[0]=0x01;
    data[1]=len+6;
    data[2]=cmd;
    data[3]=options;
    
    memcpy((data+4), inputData, len);
    
    
    crc = crc16ccitt(data, len+4);
    
    data[len+4]=(crc&0xFF);
    data[len+5]=(crc>>8);
    
    
    NSString *logString = [@"" stringByAppendingFormat:@"sending: "];
    int i=0;
    for (i=0; i<(sizeof(data)/sizeof(unsigned char)); i++) {
        logString =  [logString stringByAppendingFormat:@"0x%02x ",data[i]];
    } logString = [logString stringByAppendingFormat:@"\n"];
    
    [[MWMetaWatch sharedWatch]appendToLog:logString];

    NSLog(@"%@",logString);
    
    NSData *frame = [NSData dataWithBytes:(void*)data length:len+6];
    
    for (CBCharacteristic *c in _service.characteristics) {
        if ([c.UUID isEqual:[CBUUID UUIDWithString:kMWWatchCharacteristicUUID]]) {
            [_device writeValue:frame forCharacteristic:c type:CBCharacteristicWriteWithResponse];
        }

    }
}


#pragma mark CBCentralManagerDelegate

-(void)centralManagerDidUpdateState:(CBCentralManager *)central {
    // FIXME: handle device capabilities 
}

-(void)centralManager:(CBCentralManager *)central didRetrievePeripherals:(NSArray *)peripherals{
    NSLog(@"%@",peripherals);
}

-(void)centralManager:(CBCentralManager *)central didRetrieveConnectedPeripherals:(NSArray *)peripherals{
    NSLog(@"%@",peripherals);
}

-(void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    NSLog(@"%@, didFindDevice %@ (%@)",self,peripheral.name, peripheral.UUID);
    
    NSNumber *boolYES = [NSNumber numberWithBool:YES];
    NSDictionary *dict = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObject:boolYES]
                                                     forKeys:[NSArray arrayWithObject:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
    if (_device) {
        return;
    }
    _device = [peripheral retain];
    _device.delegate = self;
    [central connectPeripheral:_device options:dict];
}

-(void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"didConnect: %@",peripheral);
    [_device discoverServices:nil];    
}

-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"didDisconnect: %@",peripheral);

    [_device release];
    _device = nil;
    
    [self.delegate performSelector:@selector(connectionControllerDidCloseChannel:) withObject:self];

}

-(void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"didFailConnection:%@",error);
}



#pragma mark - CBPeripheralDelegate 

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    for (CBService *service in peripheral.services) {
        NSLog(@"didFindService: %@",service.UUID);
        _service = [service retain];
        [_device discoverCharacteristics:nil forService:service];
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    for (CBCharacteristic *c in service.characteristics) {
        NSLog(@"didDiscoverCharceristic: %@ forService:%@",c.UUID, service.UUID);
        
        if ([c.UUID isEqual:[CBUUID UUIDWithString:kMWWatchCharacteristicUUID]]) {
            [self.delegate performSelector:@selector(connectionControllerDidOpenChannel:) withObject:self];
        }
        
        [_device discoverDescriptorsForCharacteristic:c];
        [_device setNotifyValue:YES forCharacteristic:c];
    }

}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    for (CBDescriptor *d in characteristic.descriptors) {
        NSLog(@"didDiscoverDescriptors: %@ forCharacteristic: %@",d.UUID, characteristic.UUID);
        [_device readValueForDescriptor:d];
        _descriptor = [d retain];
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"didUpdateNotificationStateForCharacteristic: %@",characteristic.UUID);

}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"didUpdateValueForCharacteristic: %@ %@",characteristic.UUID, characteristic.value);
    [self.delegate performSelector:@selector(connectionController:didReceiveData:) withObject:self withObject:[characteristic.value copy]];

}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {
    NSLog(@"didUpdateValueForDescriptor: %@ %@",descriptor.UUID, descriptor.value);
    [self.delegate performSelector:@selector(connectionController:didReceiveData:) withObject:self withObject:[descriptor.value copy]];
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"didWriteValueForCharacteristic: %@ error: %@",characteristic.UUID,error);
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {
    NSLog(@"didWriteValueForDescriptor: %@ error: %@",descriptor.UUID,error);
}

@end
