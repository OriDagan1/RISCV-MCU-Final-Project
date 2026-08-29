#include <stdio.h>
#define SIZE 8


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
	
	while(1);
}




