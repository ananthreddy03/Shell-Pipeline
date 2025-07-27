#!/bin/bash 

start_time=$(date + %s)
set -e
set -o pipefail

cd /path/to/your/directory

#Define the directories 
RAW_DATA_DIR="/path/to/your/data"
TRIMMED_DATA_DIR="./Trimmed_Data"
RESULTS_DIR="./Results"
DB_DIR="./kraken2_db"
REPORT_FILE="${RESULTS_DIR}/classification_report.text"

echo "Creating the required directories"
mkdir -p $RAW_DATA_DIR $TRIMMED_DATA_DIR $RESULTS_DIR $RESULTS_DIR/QC $RESULTS_DIR/QC_TRIMMED $RESULTS_DIR/MULTIQC_REPORT							
mkdir k2_standard_8gb_20241228 Data_Visualization

#Quality Check with FastQC
echo "[1/10] [Fastqc] - Initiating Quality check!"
fastqc ${RAW_DATA_DIR}/*.fastq -o ${RESULTS_DIR}/QC || { echo "FastQC failed!"; exit 1; }
echo "[1/10] [Fastqc] - Initial Quality check completed!"

#Trimming 
echo "[2/10] [Trimmomatic] - Initiating Trimming and Quality Filtering!"
FWD_READ=$(find $RAW_DATA_DIR -iname "*fwd*.fastq" | head -n1)
REV_READ=$(find $RAW_DATA_DIR -iname "*bwd*.fastq" | head -n1)

if [[ -z "$FWD_READ" || -z "$REV_READ" ]]; then
  echo "Forward or Reverse Fastq files not found. EXITING! "
  exit 1
fi 

FWD_BASE=$(basename "$FWD_READ" .fastq)
REV_BASE=$(basename "$REV_READ" .fastq)

java -jar /usr/local/bin/trimmomatic-0.39.jar PE -threads 4 -phred33 \
  "$FWD_READ""$REV_READ" \
  ${TRIMMED_DATA_DIR}/${FWD_BASE}_paired.fastq ${TRIMMED_DATA_DIR}/${FWD_BASE}_unpaired.fastq \
  ${TRIMMED_DATA_DIR}/${REV_BASE}_paired.fastq ${TRIMMED_DATA_DIR}/${REV_BASE}_unpaired.fastq \
  TRAILING:10 || { echo "Trimmomatic Failed!"; exit 1; } 
echo "[2/10] [Trimmomatic] - Trimming and Quality Filtering completed!"

#Quality Check on Trimmed Data
echo "[3/10] [Fastqc] - Initiating Quality check on Trimmed Data!"
fastqc ${TRIMMED_DATA_DIR}/*.fastq -o ${RESULTS_DIR}/QC_Trimmed || { echo "FASTQC on Trimmed Data failed!"; exit 1; } 
echo "[3/10] [Fastqc] - Quality check on Trimmed Data completed!"

#Generating Comprehensive Report 
echo "[4/10] [MultiQC] - Generating MultiQC report"
multiqc ${RESULTS_DIR}/QC_Trimmed -o ${RESULTS_DIR}/MultiQC_Report || { echo "MultiQC failed!"; exit 1; }
echo "[4/10] [MultiQC] - MultiQC report generated!"

#Fastq-join
echo "[5/10] [Fastq-join] - Merging paired end reads using Fastq-join!"
FWD_JOIN=$(find $TRIMMED_DATA_DIR -iname "*fwd*_paired.fastq" | head -n1)
REV_JOIN=$(find $TRIMMED_DATA_DIR -iname "*bwd*_paired.fastq" | head -n1)

if [[ -z "$FWD_JOIN" || -z "$REV_JOIN" ]]; then
  echo "Paired end reads not found for merging. EXITING!"
  exit 1
fi

fastq-join "$FWD_JOIN" "$REV_JOIN" -o ${TRIMMED_DATA_DIR}/merged.%f || { echo "Fastq-join failed!"; exit 1; }
echo "[5/10] [Fastq-join] - Merged paired end reads!"

#Downloading Standard Kraken2 DB
echo "[6/10] [Kraken2] - Downloading Standard Kraken2 database (Capped at 8GB) "
wget https://genome-idx.s3.amazonaws.com/kraken/k2_standard_08gb_20241228.tar.gz || { echo "Download failed!"; exit 1; }
echo "[6/10] [Kraken2] - Kraken2 database downloaded!"

echo "[7/10] [Kraken2] - Extracting Kraken2 database!"
tar -xvzf k2_standard_08gb_20241228.tar.gz -C /path/to/your/directory/k2_standard_8gb_20241228 || { echo "Extraction failed!"; exit 1; }
echo "[7/10] [Kraken2] - Kraken2 database extracted!"

#Run Kraken2
MERGED_FASTQ=$(find $TRIMMED_DATA_DIR -iname "merged.join.fastq" | head -n1)

if [[ ! -f "$MERGED_FASTQ" ]]; then
  echo "Merged FASTQ file not found. Exiting."
  exit 1
fi

export KRAKEN2_DB_PATH=${DB_DIR}/k2_standard_8gb_20241228

echo "[8/10] [Kraken2] - Initiating Kraken2 Classification!"
kraken2 --db $KRAKEN2_DB_PATH --threads 4 \
  --report ${RESULTS_DIR}/standard8_report.txt \
  --output ${RESULTS_DIR}/standard8_output.txt \
  "$MERGED_FASTQ" || { echo "Kraken2 classification failed!"; exit 1; }
echo "[8/10] [Kraken2] - Reads were successfully classified!"
echo "[9/10] [Kraken2] - Classification report and output files are generated!"


#Pavian
echo "Launch Pavian for interactive visualization (open in browser and upload the  dot txt file)"


echo "[10/10] [Clean-up] - Cleaning up the intermediate files!"
rm -rf ${TRIMMED_DATA_DIR}/*_paired.fastq ${TRIMMED_DATA_DIR}/*_unpaired.fastq ${TRIMMED_DATA_DIR}/*.un1f ${TRIMMED_DATA_DIR}/*.un2f ${RESULTS_DIR}/standard8_output.txt
sleep 2
echo "[10/10] [Clean-up] - Cleanup completed!"
echo "All steps completed successfully! "

end_time=$(date +%s)
elapsed=$((end_time - start_time))

echo "The Pipeline has been successfully executed..!"
echo "$((elapsed / 60)) minutes and $((elapsed % 60)) seconds elapsed!"
