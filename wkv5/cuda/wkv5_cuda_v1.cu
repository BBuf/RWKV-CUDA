#include <stdio.h>
#include <assert.h>

template <typename F>
__global__ void kernel_forward(const int B, const int T, const int C, const int H,
                               const F *__restrict__ const _r, const F *__restrict__ const _k, const F *__restrict__ const _v, const F *__restrict__ const _w, const F *__restrict__ const _u,
                               F *__restrict__ const _y)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int _b = idx / C;
    const int _h = (idx / N) % H;
    const int _i = idx % N;

    const int _o0 = _b*T*C + _h*N;
    const int _o1 = _h*N;
    const F *__restrict__ const k = _k + _o0;
    const F *__restrict__ const v = _v + _o0 + _i;
    const F *__restrict__ const r = _r + _o0;
    F *__restrict__ const y = _y + _o0 + _i;

    float state[N] = {0};   

    for (int __t = 0; __t < T; __t++)
    {
        const int _t = __t*C;
        const F vv = v[_t];

        for (int _j = 0; _j < N; _j++) 
        {
            const int j = _t + _j;
            const int m = _o1 + _j;

            const float x = k[j] * vv;
            const float s = state[_j];
            
            atomicAdd(y + _t, r[j] * (_u[m] * x + s));
            state[_j] = s * _w[m] + x;
        }
    }
}

template <typename F>
__global__ void kernel_backward (const int B, const int T, const int C, const int H,
    const F *__restrict__ const r, const F *__restrict__ const k, const F *__restrict__ const v, const F *__restrict__ const w, const F *__restrict__ const wwww, const F *__restrict__ const _u, const F *__restrict__ const gy,
    F *__restrict__ const gr, F *__restrict__ const gk, F *__restrict__ const gv, F *__restrict__ const gw, F *__restrict__ const gu)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int b = idx / C;
    const int h = (idx / N) % H;
    const int n = idx % N;
    
    const F u1 = _u[h*N + n];
    const F w1 = w[h*N + n];
    const F wwww1 = wwww[h*N + n];
    F w_pow[4096] = {0.0f};
    for (int t =0;  t < T; t++){
        w_pow[t] = pow(w1, t);
    }

    for (int t = 0; t < T; t++) {
        const int index1 = b*T*H*N + t*H*N + h*N;
        const F* v1 = v + index1;
        const F* k1 = k + index1;
        const F* r1 = r + index1;
        const F* gy1 = gy + index1;
        F* gr1 = gr + index1;
        F* gk1 = gk + index1;
        F* gv1 = gv + index1;

        for (int nn = 0; nn < N; nn++) {
            for (int tt = 0; tt <= t; tt++) {
                F w_pow_1 = t-tt-1 >= 0 ? w_pow[t-tt-1] : pow(w1, t-tt-1);
                F ww = (tt == t) ? u1 : w_pow_1;
                
                gr1[n] += ww * k[b*T*H*N + tt*H*N + h*N + n] *
                    v[b*T*H*N + tt*H*N + h*N + nn] * gy1[nn];
            }

            for (int tt = t; tt < T; tt++) {
                F w_pow_1 = tt-t-1 >= 0 ? w_pow[tt-t-1] : pow(w1, tt-t-1);
                F ww = (tt == t) ? u1 : w_pow_1;
                
                gk1[n] += r[b*T*H*N + tt*H*N + h*N + n] * ww *
                    v1[nn] * gy[b*T*H*N + tt*H*N + h*N + nn];

                ww = (tt == t) ? _u[h*N + nn] : pow(w[h*N + nn], tt-t-1);
                
                gv1[n] += r[b*T*H*N + tt*H*N + h*N + nn] * ww *
                    k1[nn] * gy[b*T*H*N + tt*H*N + h*N + n];
            }

            atomicAdd(gu + h*N + n, r1[n] * k1[n] *
                    v1[nn] * gy1[nn]);

            for (int tt = 0; tt < t-1; tt++) {
                F w_pow_1 = t-tt-1 >= 0 ? w_pow[t-tt-1] : pow(w1, t-tt-1);
                F ww = (t-tt-1) * wwww1 * w_pow_1;

                atomicAdd(gw + h*N + n, r1[n] * ww * k[b*T*H*N + tt*H*N + h*N + n] *
                    v[b*T*H*N + tt*H*N + h*N + nn] * gy1[nn]);
            }
        }
    }
}

void cuda_forward(int B, int T, int C, int H, float *r, float *k, float *v, float *w, float *u, float *y)
{
    dim3 threadsPerBlock( min(B*C, 32) );
    assert(B * C % threadsPerBlock.x == 0);
    dim3 numBlocks(B * C / threadsPerBlock.x);
    kernel_forward<<<numBlocks, threadsPerBlock>>>(B, T, C, H, r, k, v, w, u, y);
}

void cuda_backward(int B, int T, int C, int H, float *r, float *k, float *v, float *w, float *ww, float *u, float *gy, float *gr, float *gk, float *gv, float *gw, float *gu)
{
    dim3 threadsPerBlock( min(B*C, 32) );
    assert(B * C % threadsPerBlock.x == 0);
    dim3 numBlocks(B * C / threadsPerBlock.x);
    kernel_backward<<<numBlocks, threadsPerBlock>>>(B, T, C, H, r, k, v, w, ww, u, gy, gr, gk, gv, gw, gu);
}
