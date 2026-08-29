#include <stdio.h>
#define VERIFICATION_METHOD 1   // 1- DTCM content print, 2- Objects regular print
#define DEC_FORMAT 0            // 0- printf hexadecimal format,  1- printf decimal format
#define SIZE 8


void printArr(int arr[], unsigned int size, char* arr_name);
void printArrDTCM(int arr[], unsigned int size);


int arr1[SIZE]={1,2,3,4,5,6,7,8};
int arr2[SIZE]={8,7,6,5,4,3,2,1};
int res1[SIZE], res2[SIZE], res3[SIZE];


int main(){
	int i;
	
	for(i=0; i<SIZE; i++){
		res1[i] = arr1[i] / arr2[i];
		res2[i] = arr1[i] * arr2[i];
		res3[i] = arr1[i] % arr2[i];
	}


	#if VERIFICATION_METHOD == 1
	  printArrDTCM(arr1,SIZE);
	  printArrDTCM(arr2,SIZE);
		printArrDTCM(res1,SIZE);
		printArrDTCM(res2,SIZE);
		printArrDTCM(res3,SIZE);
	#elif VERIFICATION_METHOD == 2
	  printArr(arr1,SIZE,"arr1");
	  printArr(arr2,SIZE,"arr2");
		printArr(res1,SIZE,"res1[i] = arr1[i] / arr2[i]");
		printArr(res2,SIZE,"res2[i] = arr1[i] * arr2[i]");
		printArr(res3,SIZE,"res3[i] = arr1[i] \% arr2[i]");
	#endif

	
	return 0;
}

/*===============================================
                Application verification
=================================================*/
void printArr(int arr[], unsigned int size, char* arr_name){
	printf("%s = ",arr_name);
	for(int i=0; i<size; i++){ 
  	#if DEC_FORMAT == 1
			printf("%-d  ",arr[i]);
		#elif DEC_FORMAT == 0
			printf("%-x  ",arr[i]);
		#endif
	}
  printf("\n");
}

void printArrDTCM(int arr[], unsigned int size){
	for (int i = 0; i < size; i++) {
		#if DEC_FORMAT == 1
			printf("%d\n",arr[i]);
		#elif DEC_FORMAT == 0
			printf("%08x\n",arr[i]);
		#endif
	}
}



