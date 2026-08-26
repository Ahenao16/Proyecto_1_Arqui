#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

//Variable para alinear el array a 32 bytes
#define ALIGNMENT 32

//El programa recibe como argumentos el nombre del programa y el archivo .dat que sera analizado
int main(int argc, char *argv[])
{
    //Se verifica que el conteo de argumentos argc sea = 2 para verificar que se colocara la dir del archivo .dat
    //de lo contrario se genera una excepcion y se muestra la manera correcta de ejecutar
    if (argc != 2) {
        fprintf(stderr, "Para ejecutar: %s numeros.dat\n", argv[0]);
        return EXIT_FAILURE;
    }

    //Se guarda en filename la dirección donde está almacenado el texto/nombre del .dat
    // Se abre el file y se verifica que la apertura del archivo no fallara
    const char *filename = argv[1];

    FILE *file = fopen(filename, "r");

    if (file == NULL) {
        perror("Error al abrir el archivo");
        return EXIT_FAILURE;
    }

    // Se cuenta la cantidad de datos del archivo. Se comprueba si los datos son floats
    int n = 0;
    float temp;

    while (1) {
        int result = fscanf(file, "%f", &temp); //si los numeros son floats fscanf devuelve un 1

        if (result == 1) {
            n++;
        } else if (result == EOF) { //si se termino el file termina de verificar
            break;
        } else {
            fprintf(stderr, "Error: el archivo contiene un valor que no es un numero.\n");
            fclose(file);
            return EXIT_FAILURE;
        }
    }

    // Se verifica si el archivo no esta vacio
    if (n == 0) {
        fprintf(stderr, "El archivo no contiene datos.\n");
        fclose(file);
        return EXIT_FAILURE;
    }

    // se declara un puntero que apunta a floats
    float *arr;

    //alineamiento de memoria en ram. posix_memalign recibe en orden: direccion donde se guarda el puntero, alineamiento y cantidad de bytes
    if (posix_memalign(
            (void **)&arr, //Obtiene la dirección de arr y la convierte al tipo void** que espera posix_memalign, para que esta pueda guardar en arr la dirección de la memoria reservada.
            ALIGNMENT, //Se quiere que la posicion de memoria sea multiplo de 32 porque AVX2 utiliza registros YMM de 256 bits (256/8)
            n * sizeof(float)) != 0) {

        fprintf(stderr, "Error reservando memoria.\n");
        fclose(file);
        return EXIT_FAILURE;
    }

    //regresamos al principio del archivo
    rewind(file);

    //Se guardan los datos en el array creado luego de reservar el espacio.
    for (int i = 0; i < n; i++) {
        fscanf(file, "%f", &arr[i]);
    }
    fclose(file);

    //Esta es una seccion de verificacion para imprimir en consola, probablemente luego se elimine
    printf("Archivo: %s\n", filename);
    printf("Cantidad de elementos: %d\n", n);
    printf("Direccion del array: %p\n", (void *)arr);

    printf("\nPrimeros elementos:\n");

    for (int i = 0; i < n; i++) {
        printf("arr[%d] = %f\n", i, arr[i]);
    }

    free(arr); //Libera la memoria del array, dejarlo al final del programa para no desperdiciar memoria

    return EXIT_SUCCESS;
}