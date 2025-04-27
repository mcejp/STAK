#include <arpa/inet.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "listener.h"

static int listen_fd, client_fd = -1;

void listener_init(void) {
    listen_fd = socket(AF_INET, SOCK_STREAM, 0);

    if (listen_fd < 0) {
        perror("create socket");
        exit(-1);
    }

    int opt = 1;
    int rc = setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    if (rc < 0) {
        perror("setsockopt");
        exit(-1);
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));

    addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_ANY);
	addr.sin_port = htons(5000);

    rc = bind(listen_fd, (struct sockaddr *) &addr, sizeof(addr));

    if (rc < 0) {
        perror("bind");
        exit(-1);
    }

    rc = listen(listen_fd, 1);

    if (rc < 0) {
        perror("listen");
        exit(-1);
    }

    fprintf(stderr, "listening on port %d\n", ntohs(addr.sin_port));
}

void listener_shutdown(void) {
}

void listener_tick(void) {
    if (client_fd < 0) {
        struct pollfd pfd;
        pfd.fd = listen_fd;
        pfd.events = POLLIN;

        int ready = poll(&pfd, 1, 0);
        if (ready == -1) {
            perror("poll");
            exit(-1);
        }

        if (ready == 0) {
            return;
        }

        client_fd = accept(listen_fd, NULL, NULL);
    }
}

int listener_poll_byte(void) {
    if (client_fd < 0) {
        return -1;
    }

    struct pollfd pfd;
    pfd.fd = client_fd;
    pfd.events = POLLIN;

    int ready = poll(&pfd, 1, 0);
    if (ready == -1) {
        perror("poll");
        close(client_fd);
        client_fd = -1;
        return -1;
    }

    if (ready == 0) {
        return -1;
    }

    // receive
    // TODO: receive multiple bytes in one go
    uint8_t ch;
    int rc = recv(client_fd, &ch, 1, 0);

    if (rc < 0) {
        perror("recv");
        close(client_fd);
        client_fd = -1;
        return -1;
    }
    else if (rc == 0) {
        fprintf(stderr, "debugger disconnected\n");
        close(client_fd);
        client_fd = -1;
        return -1;
    }

    return ch;
}

void listener_send(uint8_t const* buffer, int count) {
    if (send(client_fd, (void*) buffer, count, 0) != count) {
        perror("send");
    }
}
