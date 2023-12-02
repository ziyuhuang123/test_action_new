#include <cute/tensor.hpp>
#include <cuda_runtime.h>
#include <cublas_v2.h>
#include <iostream>

// z = ax + by + c
template <int kNumElemPerThread = 8>
__global__ void vector_add_local_tile_multi_elem_per_thread_half(
    half *z, int num, const half *x, const half *y, const half a, const half b, const half c) {
  using namespace cute;

  int idx = threadIdx.x + blockIdx.x * blockDim.x;
  if (idx >= num / kNumElemPerThread) { // 未处理非对齐问题
    return;
  }

  Tensor tz = make_tensor(make_gmem_ptr(z), make_shape(num));
  Tensor tx = make_tensor(make_gmem_ptr(x), make_shape(num));
  Tensor ty = make_tensor(make_gmem_ptr(y), make_shape(num));

  Tensor tzr = local_tile(tz, make_shape(Int<kNumElemPerThread>{}), make_coord(idx));
  Tensor txr = local_tile(tx, make_shape(Int<kNumElemPerThread>{}), make_coord(idx));
  Tensor tyr = local_tile(ty, make_shape(Int<kNumElemPerThread>{}), make_coord(idx));

  Tensor txR = make_tensor_like(txr);
  Tensor tyR = make_tensor_like(tyr);
  Tensor tzR = make_tensor_like(tzr);

  // LDG.128
  copy(txr, txR);
  copy(tyr, tyR);

  half2 a2 = {a, a};
  half2 b2 = {b, b};
  half2 c2 = {c, c};

  auto tzR2 = recast<half2>(tzR);
  auto txR2 = recast<half2>(txR);
  auto tyR2 = recast<half2>(tyR);

#pragma unroll
  for (int i = 0; i < size(tzR2); ++i) {
    // two hfma2 instruction
    tzR2(i) = txR2(i) * a2 + (tyR2(i) * b2 + c2);
  }

  auto tzRx = recast<half>(tzR2);

  // STG.128
  copy(tzRx, tzr);
}

int main() {
    const int kNumElemPerThread = 8; // 定义此常量

    // 定义向量大小
    int num = 1024; // 示例大小

    // 为向量分配内存
    half *x, *y, *z;
    cudaMallocManaged(&x, num * sizeof(half));
    cudaMallocManaged(&y, num * sizeof(half));
    cudaMallocManaged(&z, num * sizeof(half));

    // 初始化向量 x 和 y
    for (int i = 0; i < num; ++i) {
        x[i] = half(i);  // 示例数据
        y[i] = half(num - i);  // 示例数据
    }

    // 定义操作的系数
    half a = half(1.0), b = half(2.0), c = half(3.0);

    // 定义 kernel 的执行配置
    int threadsPerBlock = 256;
    int elementsPerBlock = kNumElemPerThread * threadsPerBlock;
    int numBlocks = (num + elementsPerBlock - 1) / elementsPerBlock;

    // 调用 kernel
    vector_add_local_tile_multi_elem_per_thread_half<kNumElemPerThread><<<numBlocks, threadsPerBlock>>>(
        z, num, x, y, a, b, c);
    cudaDeviceSynchronize();  // 等待 GPU 完成

    // 验证结果（可选）
    bool valid = true;
    for (int i = 0; i < num; ++i) {
        if (static_cast<float>(z[i]) != static_cast<float>(a) * static_cast<float>(x[i]) + static_cast<float>(b) * static_cast<float>(y[i]) + static_cast<float>(c)) {
            std::cout << "Mismatch at " << i << ": " << static_cast<float>(z[i]) << " != " << (static_cast<float>(a) * static_cast<float>(x[i]) + static_cast<float>(b) * static_cast<float>(y[i]) + static_cast<float>(c)) << std::endl;
            valid = false;
            break;
        }
    }
    if (valid) {
        std::cout << "Results are correct!" << std::endl;
    }

    // 清理
    cudaFree(x);
    cudaFree(y);
    cudaFree(z);

    return 0;
}
