d := $(dir $(lastword $(MAKEFILE_LIST)))

GTEST_SRCS += $(addprefix $(d), occstore-test.cc)

$(d)occstore-test: $(o)occstore-test.o \
    $(LIB-strong-store) \
    $(OBJS-store-strongstore) \
    $(OBJS-store-common) \
    $(LIB-store-common) \
    $(LIB-store-backend) \
    $(LIB-message) \
    $(GTEST_MAIN)

TEST_BINS += $(d)occstore-test