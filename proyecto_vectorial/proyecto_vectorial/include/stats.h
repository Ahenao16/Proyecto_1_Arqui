/*Para qué sirve: es el archivo de cabecera de C que declara las firmas de las tres funciones que vas a escribir en ensamblador:
Es el "contrato" entre el mundo C (driver.c) y el ensamblador (.asm). El compilador de C lee este .h para saber cómo llamar a
funciones que no están escritas en C — confía en que en algún .o va a existir una función con ese nombre, esos parámetros y esa convención de llamada.
*/


#ifndef STATS_H
#define STATS_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Firmas de los kernels de computo. Estas MISMAS firmas deben estar
 * implementadas tanto en asm/scalar/stats_scalar.asm como en
 * asm/vector/stats_vector.asm, respetando la convencion de llamada
 * System V AMD64 ABI:
 *
 *   Enteros/punteros (en orden): rdi, rsi, rdx, rcx, r8, r9
 *   Flotantes (en orden, aparte): xmm0, xmm1, xmm2, ...
 *   Valor de retorno float: xmm0
 *
 * sum_array:
 *   rdi = arr, esi = n              -> retorna la suma en xmm0
 * registro rdi = arr: recibe en el registro de 64 bits el puntero del arreglo de entrada (arr)
   esi = n: recibe en el registro de 32 bits el numero de elementos (n) que contiene el arreglo
   retorna la suma en xmm0: devuelte el resultado flotante acumulado en el registro del puntero flotante xmm0

 * compute_stats:
 *   rdi = arr, esi = n, rdx = mean*, rcx = var*, r8 = min*, r9 = max*
 *   (var = varianza POBLACIONAL: var = sum((x - mean)^2) / n)
 *   Caso borde: si n == 0, escriba 0.0 en mean/var/min/max.
     rdx = var*, r8= min*, r9= max*: punteros de memoria donde la subrutina debe escribir los resultados calculados, 
     media, varianza poblacional, valor minimo y valor maximo ademas el caso borde
 *
 * normalize_array:
 *   rdi = in, rsi = out, edx = n, xmm0 = mean, xmm1 = stddev
 *   out[i] = (in[i] - mean) / stddev
 *   Caso borde: si stddev == 0.0, copie in[i] en out[i] tal cual
 *   (evite division por cero)
 rdi = in: Puntero al arreglo de entrada original.
 rsi = out: Puntero al arreglo de salida donde se guardarán los datos normalizados.
 edx = n: Tamaño del arreglo.
 xmm0 = mean: Valor de la media ya calculado que se pasa como argumento de entrada en punto flotante.
 xmm1 = stddev: Valor de la desviación estándar de entrada.


 */

float sum_array(const float *arr, int n);

void compute_stats(const float *arr, int n,
                    float *mean, float *var, float *min, float *max);

void normalize_array(const float *in, float *out, int n,
                      float mean, float stddev);

#ifdef __cplusplus
}
#endif

#endif /* STATS_H */
