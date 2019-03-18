##############################################################################
# This script is to test the imputation rates for various panels
# Data:
#  1. Full panel: 606k, 828ID
#  2. 18k \in 50k \in 606k
#  3. 8k are majorly \in 18k
# Method:
#  1. Extract 18k, & 50k results of the 345 ID from genotypes of  828ID
#  2. impute and compare
##############################################################################

prepare-a-working-directory(){
    ############################################################
    # Create a working directory
    work=$base/work/step--8k-18k-50k-hd
    mkdir -p $work
    cd $work

    # soft link the genotypes here
    for i in $G600K; do
	ln -sf $genotypes/$i .
    done
}


make-id-maps(){
    echo collect ID
    grep -v ^# $genotypes/genotyped.id |
	gawk '{if(length($5)>5) print $5, $2}' >828.id

    grep -v ^# $genotypes/genotyped.id |
	gawk '{if(length($5)>5 && length($4)<5) print $5, $2}' >483.id

    grep -v ^# $genotypes/genotyped.id |
	gawk '{if(length($5)>5 && length($4)>5) print $5, $2}' >345.id
    
    echo Make maps
    tail -n+2 $maps/current.map |
    	gawk '{print $13, $11, $12}' >hd.map

    cat hd.map |
	$bin/subMap $maps/8k.snp     >8k.map
    
    cat hd.map |
	$bin/subMap $maps/18k.snp    >18k.map

    cat hd.map |
	$bin/subMap $maps/50k.snp    >50k.map
}
    

collect-828-hd-genotypes(){
    echo Create beagle files
    $bin/mrg2bgl 828.id hd.map $G600K

    for chr in {26..1}; do
	java -jar $bin/beagle2vcf.jar $chr $chr.mrk $chr.bgl - |
	    gzip -c >tmp.$chr.vcf.gz
	
	java -jar $bin/beagle.jar \
	     gt=tmp.$chr.vcf.gz \
	     ne=$ne \
	     out=828.$chr
    done
}


collect-step-genotypes(){
    # find the HD genotypes of those who only genotyped with HD chips
    # step genotypes of 483 ID, with prefix 'h'
    for panel in 18k 50k hd; do
	echo genotypes of 483 ID with $panel panel
	$bin/mrg2bgl 483.id $panel.map $G600K

	for chr in {26..1}; do
	    java -jar $bin/beagle2vcf.jar $chr $chr.mrk $chr.bgl - |
		gzip -c >h$panel.$chr.vcf.gz
	done
    done

    # step genotypes of 345 ID, with prefix 'l'
    for panel in 8k 18k 50k; do
	echo genotypes of 345 ID with $panel panel
	$bin/mrg2bgl 345.id $panel.map $G600K

	for chr in {26..1}; do
	    java -jar $bin/beagle2vcf.jar $chr $chr.mrk $chr.bgl - |
		gzip -c >l$panel.$chr.vcf.gz
	done
    done
}


mrg-n-imp(){
    # $1: of lower density map
    # $2: of higher density map
    # $3: chr
    $bin/ljvcf <(zcat h$2.$3.vcf.gz) <(zcat l$1.$3.vcf.gz) |
	gzip -c >tmp.$chr.vcf.gz

    java -jar $bin/beagle.jar \
	 gt=tmp.$3.vcf.gz \
	 ne=$ne \
	 out=i$1-$2.$3
}


step-merge-n-impute(){
    for chr in {26..1}; do
	mrg-n-imp  8k 18k $chr
	mrg-n-imp  8k 50k $chr
	mrg-n-imp  8k  hd $chr
	mrg-n-imp 18k 50k $chr
	mrg-n-imp 18k  hd $chr
	mrg-n-imp 50k  hd $chr

	# 8k->18k->50k->hd
	zcat i8k-18k.$chr.vcf.gz |
	    $bin/subid 345.id |
	    gzip -c >l8k-18k.$chr.vcf.gz
	mrg-n-imp 8k-18k 50k $chr

	zcat i8k-18k-50k.$chr.vcf.gz |
	    $bin/subid 345.id |
	    gzip -c >l8k-18k-50k.$chr.vcf.gz
	mrg-n-imp 8k-18k-50k hd $chr

	# 18k->50k->hd
	zcat i18k-50k.$chr.vcf.gz |
	    $bin/subid 345.id |
	    gzip -c >l18k-50k.$chr.vcf.gz
	mrg-n-imp 18k-50k hd $chr
    done
}


error-rates(){
    for chr in {1..26}; do
	echo $chr
    done
}


step-debug(){
    prepare-a-working-directory

    collect-step-genotypes

    step-merge-n-impute
}


step-impute(){
    prepare-a-working-directory
    
    make-id-maps
    
    collect-828-hd-genotypes

    collect-step-genotypes

    step-merge-n-impute
}


compare-imputed-and-hd-to-find-bad-loci(){
    # the 345 ID who were genotyped with both LD and HD chips
    cat $genotypes/$idinfo |
        gawk '{if(length($3)>5 && length($4)>5) print $2}' > 345.id

    # the imputed loci and their HD and imputed genotypes
    rm -f *.snp			# if exist
    for chr in {1..26}; do
	zcat 345.$chr.vcf.gz |
	    tail -n+11 |
	    gawk '{print $3}' >>345-hd.snp
	zcat ild.$chr.vcf.gz |
	    tail -n+11 |
	    gawk '{print $3}' >>345-ld.snp
	zcat imp.$chr.vcf.gz |
	    tail -n+11 |
	    gawk '{print $3}' >>imp-hd.snp
	zcat 345.$chr.vcf.gz |
	    tail -n+11 |
	    gawk -v chr=$chr '{print $3, chr}' >>snp-chr.snp
    done

    cat 345-hd.snp 345-ld.snp imp-hd.snp |
	sort |
	uniq -c |
	gawk '{if($1==3) print $2}' >shared.snp

    cat 345-hd.snp shared.snp |
	sort |
	uniq -c |
	gawk '{if($1==1) print $2}' >ref.snp

    cat imp-hd.snp shared.snp |
	sort |
	uniq -c |
	gawk '{if($1==1) print $2}' >imp.snp

    cat ref.snp imp.snp |
	sort |
	uniq -c |
	gawk '{if($1==2) print $2}' >check.snp

    cat snp-chr.snp |
	$bin/pksnp check.snp >snp.chr

    # then find the HD control and imputed genotypes
    zcat 345.{1..26}.vcf.gz |
	$bin/subvcf 345.id check.snp >345.gt

    zcat imp.{1..26}.vcf.gz |
	$bin/subvcf 345.id check.snp >imp.gt

    # calculate: 
    # SNP chr allele-frq gt-error allele-error
    paste snp.chr 345.gt imp.gt |
	gawk '{print $1, $2, $4, $6}' |
	$bin/impErr >err.txt
}