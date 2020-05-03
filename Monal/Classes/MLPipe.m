//
//  MLPipe.m
//  Monal
//
//  Created by Thilo Molitor on 03.05.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPipe.h"

#define kPipeBufferSize 4096

@interface MLPipe()
{
    //buffer for writes to the output stream that can not be completed
    uint8_t * _outputBuffer;
    size_t _outputBufferByteCount;
}

@property (atomic, strong) NSInputStream* input;
@property (atomic, strong) NSOutputStream* output;
@property (assign) id <NSStreamDelegate> delegate;

@end

@implementation MLPipe

-(id) initWithInputStream:(NSInputStream*)inputStream andOuterDelegate:(id <NSStreamDelegate>)outerDelegate {
    _input = inputStream;
    _delegate = outerDelegate;
    _outputBufferByteCount = 0;
    [_input setDelegate:self];
    [_input scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

-(void)dealloc
{
    DDLogInfo(@"Deallocating pipe");
    [self close];
}

-(void)close
{
    DDLogInfo(@"Closing pipe");
    [self cleanupOutputBuffer];
    @try
    {
        if(_input)
        {
            DDLogInfo(@"Closing pipe: input end");
            [_input setDelegate:nil];
            [_input removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
            [_input close];
            _input = nil;
        }
        if(_output)
        {
            DDLogInfo(@"Closing pipe: output end");
            [_output setDelegate:nil];
            [_output removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
            [_output close];
            _output = nil;
        }
        DDLogInfo(@"Pipe closed");
    }
    @catch(id theException)
    {
        DDLogError(@"Exception while closing pipe");
    }
}

-(NSInputStream*) getNewEnd {
    //make current output stream orphan
    if(_output)
    {
        DDLogInfo(@"Pipe making output stream orphan");
        [_output setDelegate:nil];
        [_output removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        _output = nil;
    }
    [self cleanupOutputBuffer];
    
    //create new stream pair and schedule it properly
    DDLogInfo(@"Pipe creating new stream pair");
    NSInputStream* retval;
    NSOutputStream* localOutput;
    [NSStream getBoundStreamsWithBufferSize:kPipeBufferSize inputStream:&retval outputStream:&localOutput];
    _output = localOutput;
    [_output setDelegate:self];
    [_output scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    return retval;
}

-(NSNumber*) drainInputStream {
    NSInteger drainedBytes = 0;
    uint8_t* buf=malloc(kPipeBufferSize+1);
    NSInteger len = 0;
    do
    {
        if(![_input hasBytesAvailable])
            break;
        len = [_input read:buf maxLength:kPipeBufferSize];
        DDLogVerbose(@"drained %ld bytes", (long)len);
        if(len>0) {
            drainedBytes += len;
            buf[len]='\0';      //null termination for log output of raw string
            DDLogVerbose(@"got raw drained string '%s'", buf);
        }
    } while(len>0 && [_input hasBytesAvailable]);
    free(buf);
    DDLogVerbose(@"done draining %ld bytes", (long)drainedBytes);
    return @(drainedBytes);
}

-(void) cleanupOutputBuffer {
    if(_outputBuffer)
    {
        DDLogVerbose(@"Pipe throwing away data in output buffer: %ld bytes", (long)_outputBufferByteCount);
        free(_outputBuffer);
    }
    _outputBuffer = nil;
    _outputBufferByteCount = 0;
}

-(void) process {
    //only start processing if piping is possible
    if(!_output || ![_output hasSpaceAvailable])
        return;
    
    DDLogVerbose(@"starting pipe processing");
    
    //try to send remaining buffered data first
    if(_outputBufferByteCount>0)
    {
		NSInteger writtenLen=[_output write:_outputBuffer maxLength:_outputBufferByteCount];
		if(writtenLen!=-1)
		{
			if(writtenLen!=_outputBufferByteCount)		//some bytes remaining to send
			{
				memmove(_outputBuffer, _outputBuffer+(size_t)writtenLen, _outputBufferByteCount-(size_t)writtenLen);
				_outputBufferByteCount-=writtenLen;
                DDLogVerbose(@"pipe processing sent part of buffered data");
                return;
			}
			else
			{
				//dealloc empty buffer
				free(_outputBuffer);
				_outputBuffer=nil;
				_outputBufferByteCount=0;		//everything sent
				DDLogVerbose(@"pipe processing sent all buffered data");
			}
		}
		else
		{
			NSError* error=[_output streamError];
			DDLogError(@"pipe sending failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
			return;
		}
	}
    
    //return here if we have nothing to read
    if(![_input hasBytesAvailable])
    {
        DDLogVerbose(@"stopped pipe processing: nothing to read");
        return;
    }
    
    uint8_t* buf=malloc(kPipeBufferSize+1);
    NSInteger readLen = 0;
    NSInteger writtenLen = 0;
    do
    {
        readLen = [_input read:buf maxLength:kPipeBufferSize];
        DDLogVerbose(@"pipe read %ld bytes", (long)readLen);
        if(readLen>0) {
            buf[readLen]='\0';      //null termination for log output of raw string
            DDLogVerbose(@"pipe got raw string '%s'", buf);
            writtenLen = [_output write:buf maxLength:readLen];
            if(writtenLen == -1)
            {
                NSError* error=[_output streamError];
                DDLogError(@"pipe sending failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
                return;
            }
            else if(writtenLen < readLen)
            {
                DDLogVerbose(@"pipe could only write %ld of %ld bytes, buffering", (long)writtenLen, (long)readLen);
                //allocate new _outputBuffer
                _outputBuffer=malloc(sizeof(uint8_t) * (readLen-writtenLen));
                //copy the remaining data into the buffer and set the buffer pointer accordingly
                memcpy(_outputBuffer, buf+(size_t)writtenLen, (size_t)(readLen-writtenLen));
                _outputBufferByteCount=(size_t)(readLen-writtenLen);
                break;
            }
        }
    } while(readLen>0 && [_input hasBytesAvailable] && [_output hasSpaceAvailable]);
    free(buf);
    DDLogVerbose(@"pipe processing done");
}

-(void)stream:(NSStream*)stream handleEvent:(NSStreamEvent)eventCode {
    DDLogVerbose(@"Pipe stream has event");
    
    //ignore events from stale streams
    if(stream!=_input && stream!=_output)
        return;
    
    switch(eventCode)
    {
        //handle read and write events
        case NSStreamEventHasSpaceAvailable:
        {
            DDLogVerbose(@"Pipe stream has bytes to write");
            [self process];
            break;
        }
        case  NSStreamEventHasBytesAvailable:
        {
            DDLogVerbose(@"Pipe stream has bytes to read");
            [self process];
            break;
        }
        
        //handle all other events in outer stream delegate
        default:
        {
            DDLogVerbose(@"Pipe stream delegates event to outer delegate");
            [_delegate stream:stream handleEvent:eventCode];
            break;
        }
    }
}

@end