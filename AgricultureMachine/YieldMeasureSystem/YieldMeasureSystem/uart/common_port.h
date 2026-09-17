#ifndef COMMON_PORT_H
#define COMMON_PORT_H

#ifdef __cplusplus
extern "C" {
#endif

long port_open(const char *portName, const char *fmt);
void port_close(long handle);

int port_send(long handle, char *buf, int len, int flag);
int port_read(long handle, char *buf, int len, int flag);

int port_pipe(long pipefd[2]);

int port_get_list(char ***pazResult);
void port_free_list(char **result);

#ifdef __cplusplus
}
#endif

#endif // COMMON_PORT_H
