#ifndef __ID2NUM_H_
#define __ID2NUM_H_

#ifdef __cplusplus
extern "C" {
#endif
int transKey(unsigned long id, char *buf);//buf至少24字节
char transOne_1(unsigned int data);
char transOne_2(unsigned int data);
char transOne_3(unsigned int data);
char transOne_4(unsigned int data);
#ifdef __cplusplus
}
#endif


#endif
