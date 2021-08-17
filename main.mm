//    Copyright (c) 2021 udevs
//
//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, version 3.
//
//    This program is distributed in the hope that it will be useful, but
//    WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
//    General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with this program. If not, see <http://www.gnu.org/licenses/>.

#include <stdio.h>
#include <unistd.h>
#include <xpc/xpc.h>
#include <getopt.h>
#include <CoreFoundation/CoreFoundation.h>

static xpc_object_t create_encoded_obj(CFStringRef img_path, CFStringRef sig_path, CFStringRef img_type, CFStringRef request_type, CFStringRef mount_path){
    
    CFMutableDictionaryRef encoded_dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);    CFDictionarySetValue(encoded_dict, CFSTR("DeviceType"), CFSTR("DiskImage"));
    CFDictionarySetValue(encoded_dict, CFSTR("DiskImagePath"),img_path);
    CFDictionarySetValue(encoded_dict, CFSTR("DiskImageType"), img_type);
    CFDictionarySetValue(encoded_dict, CFSTR("RequestType"), request_type);
    CFDictionarySetValue(encoded_dict, CFSTR("ImageSignature"),(CFDataRef)[NSData dataWithContentsOfFile:(__bridge NSString *)sig_path]);
    
    if (mount_path){
        CFDictionarySetValue(encoded_dict, CFSTR("MountPath"), mount_path);
    }
    
    CFErrorRef err = NULL;
    CFDataRef data = CFPropertyListCreateData(kCFAllocatorDefault, encoded_dict, kCFPropertyListXMLFormat_v1_0, 0, &err);
    if (err){
        CFStringRef errorDesc = CFErrorCopyDescription(err);
        const char *errMsg = CFStringGetCStringPtr(errorDesc, kCFStringEncodingUTF8);
        fprintf(stderr, "ERROR: CFPropertyListCreateData cannot create property list - %s\n", errMsg);
        CFRelease(errorDesc);
        return NULL;
    }
    
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    
    xpc_dictionary_set_data(message, "EncodedDictionary", CFDataGetBytePtr(data), CFDataGetLength(data));
    
    return message;
}

static xpc_connection_t mounter_xpc_conn(){
    xpc_connection_t connection =
    xpc_connection_create_mach_service("com.apple.mobile.storage_mounter.xpc", NULL, 0);
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
    });
    xpc_connection_resume(connection);
    return connection;
}

static xpc_object_t send_obj(xpc_object_t message){
    xpc_connection_t mount_conn = mounter_xpc_conn();
    if (mount_conn){
        return xpc_connection_send_message_with_reply_sync(mount_conn, message);
    }
    return NULL;
}

static void print_help(){
    fprintf(stdout,
            "Usage: mountdmg [options] IMG_FILE [SIG_FILE]\n"
            "       If no SIG_FILE specified, will assume IMG_FILE.signature\n"
            "       options:\n"
            "           -t, --type <image type>:\n"
            "               Developer (default)\n"
            "               SystemDeveloper\n"
            "               Cryptex\n"
            "           -r, --request <request type>:\n"
            "               Mount (default)\n"
            "               Unmount\n"
            "           -p, --mpath <mount path>: mounted path for \"Unmount\"\n"
            "           -h, --help: help\n"
            );
    exit(-1);
}

int main(int argc, char *argv[], char *envp[]) {
    
    static struct option longopts[] = {
        { "request", required_argument, 0, 'r' },
        { "mpath", required_argument, 0, 'p' },
        { "type", required_argument, 0, 't' },
        { "help", no_argument, 0, 'h'},
        { 0, 0, 0, 0 }
    };
    
    CFStringRef signature_path = NULL;
    CFStringRef request = CFSTR("Mount");
    CFStringRef type =  CFSTR("Developer");
    CFStringRef mount_path =  NULL;
    
    int opt;
    while ((opt = getopt_long(argc, argv, "r:t:p:h", longopts, NULL)) != -1){
        switch (opt){
            case 'r':
                request = CFStringCreateWithCString(kCFAllocatorDefault, optarg, kCFStringEncodingMacRoman);
                break;
            case 't':
                type = CFStringCreateWithCString(kCFAllocatorDefault, optarg, kCFStringEncodingMacRoman);
                break;
            case 'p':
                mount_path = CFStringCreateWithCString(kCFAllocatorDefault, optarg, kCFStringEncodingMacRoman);
                break;
            default:
                print_help();
                break;
        }
    }
    
    argc -= optind;
    argv += optind;
    
    if (argc < 1) {printf("ERROR: IMG_FILE not specified!\n"); return -1;}
    
    if (access(strdup(argv[0]), F_OK) != 0) {printf("ERROR: IMG_FILE not exist!\n"); return -1;}
    CFStringRef image_path = CFStringCreateWithCString(kCFAllocatorDefault, strdup(argv[0]), kCFStringEncodingMacRoman);
    
    if (argc >= 2){
        if (access(strdup(argv[1]), F_OK) != 0) {printf("ERROR: SIG_FILE not exist!\n"); return -1;}
        signature_path = CFStringCreateWithCString(kCFAllocatorDefault, strdup(argv[1]), kCFStringEncodingMacRoman);
    }
    
    if (!signature_path){
        signature_path =  CFStringCreateWithFormat(NULL, NULL, CFSTR("%@.signature"), image_path);
        if(access(CFStringGetCStringPtr(signature_path, kCFStringEncodingUTF8), F_OK) != 0) {printf("ERROR: SIG_FILE not specified!\n"); return -1;}
    }
    
    if(access(CFStringGetCStringPtr(signature_path, kCFStringEncodingUTF8), R_OK) != 0) {printf("ERROR: SIG_FILE not readable, check permissions!\n"); return -1;}
    
    xpc_object_t msg = create_encoded_obj(image_path, signature_path, type, request, mount_path);
    
    if (msg){
        xpc_object_t reply = send_obj(msg);
        if (xpc_get_type(reply) == XPC_TYPE_DICTIONARY){
            size_t encoded_data_l;
            const void *encoded_data = xpc_dictionary_get_data(reply, "EncodedDictionary", &encoded_data_l);
            if (encoded_data){
                CFDataRef data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)encoded_data, encoded_data_l);
                CFDictionaryRef encoded_dict = (CFDictionaryRef)CFPropertyListCreateWithData(kCFAllocatorDefault, data, 0, 0, nil);
                CFStringRef status = (CFStringRef)CFDictionaryGetValue(encoded_dict, CFSTR("Status"));
                if (CFStringCompare(status, CFSTR("Success"), 0) == kCFCompareEqualTo){
                    fprintf(stdout, "%s\n", "Success");
                }else{
                    CFStringRef err = (CFStringRef)CFDictionaryGetValue(encoded_dict, CFSTR("DetailedError"));
                    fprintf(stderr, "ERROR: %s\n", CFStringGetCStringPtr(err, kCFStringEncodingUTF8));
                }
            }
        }else{
            fprintf(stderr, "ERROR: No reply received\n");
            return 1;
        }
    }else{
        return 1;
    }
    
    return 0;
}
