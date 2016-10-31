//
//  ProposalsViewCoordinator.swift
//  SPS
//
//  Created by Yaman JAIOUCH on 08/10/2016.
//  Copyright © 2016 Yaman JAIOUCH. All rights reserved.
//

import Foundation
import RealmSwift
import RxSwift
import RxCocoa
import RxDataSources

// TODO: Unit tests
class ProposalsViewCoordinator {
    
    // MARK: Properties
    
    private let proposalsStatusSynchronizer: ProposalsStatusSynchronizerType
    private let disposeBag = DisposeBag()

    // outputs
    let proposalSections: Driver<[AnimatableSection<ProposalViewModel>]>
    let isEmpty: Driver<Bool>
    let hasUnreadChanges: Driver<Bool>
    
    // inputs
    let headerTapped: PublishSubject<AnimatableSection<ProposalViewModel>> = PublishSubject()
    private let hiddenSections: Variable<[AnimatableSection<ProposalViewModel>]> = Variable([])
    
    // MARK: Initializers
    
    init(realm: Realm, proposalsStatusSynchronizer: ProposalsStatusSynchronizerType, searchInput: Observable<String?>) {
        self.proposalsStatusSynchronizer = proposalsStatusSynchronizer
        
        let results = realm.objects(Proposal.RealmObject.self)
        let resultsObservable = Observable.arrayFrom(results)

        // filter result from DB with search input string
        let searchResult = Observable.combineLatest(searchInput, resultsObservable) { (searchInput, proposals) -> [ProposalType] in
            guard let searchInput = searchInput, !searchInput.isEmpty else { return proposals }
            return proposals.filter { $0.name.lowercased().contains(searchInput.lowercased()) }
        }
        
        // map filtered result into animatable sections of ProposalViewModel
        var proposalSections = searchResult
            // separate proposals by status
            .map { proposals -> [ProposalStatusVersion: [ProposalType]] in
                let dic = proposals.reduce([:]) { (dic, proposal) -> [ProposalStatusVersion: [ProposalType]] in
                    let proposalStatusVersion = ProposalStatusVersion(status: proposal.status, swiftVersion: proposal.swiftVersion)
                    var dic = dic
                    var proposals = dic[proposalStatusVersion] ?? []
                    proposals.append(proposal)
                    dic[proposalStatusVersion] = proposals
                    
                    return dic
                }
                
                return dic
            }
            // apply a custom display order
            .map { proposals in
                return proposals.sorted() { p1, p2 in
                    var ordered = p1.key.status.displayOrder < p2.key.status.displayOrder
                    if let s1 = p1.key.swiftVersion, let s2 = p2.key.swiftVersion {
                        ordered = ordered || (!ordered && s1 > s2)
                    }
                    
                    return ordered
                }
            }
            // transform them to minimal data for our table view
            .map { proposals -> [AnimatableSection<ProposalViewModel>] in
                return proposals.map { proposal in
                    let version = proposal.key.swiftVersion != nil ? " (Swift \(proposal.key.swiftVersion!))"  : ""
                    let title = proposal.key.status.displayName + version
                    let proposalViewModels = proposal.value.map { ProposalViewModel($0) }
                    return AnimatableSection(title: title, elements: proposalViewModels)
                }
            }
        
        // collapse / expand sections
        proposalSections = Observable.combineLatest(proposalSections, hiddenSections.asObservable()) { proposalSections, hiddenSections in
            return proposalSections.map { section in
                var section = section
                section.isCollapsed = hiddenSections.contains(where: { $0.identity == section.identity })
                return section
            }
        }
        
        self.proposalSections = proposalSections.asDriver(onErrorJustReturn: [])
        
        self.isEmpty = self.proposalSections.map { sections in
            return sections.isEmpty
        }
        
        let hasUnreadPredicate = NSPredicate(format: "isNew = %@", NSNumber(booleanLiteral: true))
        self.hasUnreadChanges = Observable.from(realm.objects(RealmProposalChange.self).filter(hasUnreadPredicate))
            .map { $0.count > 0 }
            .distinctUntilChanged()
            .asDriver(onErrorJustReturn: false)
        
        // update collapsed/expanded sections state when user cliked on a section header
        // FIXME: I'm gonna vomit ... Better way please ?
        headerTapped.subscribe(onNext: { section in
            var hiddenSections = self.hiddenSections.value
            if let index = hiddenSections.index(where: { $0.identity == section.identity }) {
                hiddenSections.remove(at: index)
            } else {
                hiddenSections.append(section)
            }
            
            self.hiddenSections.value = hiddenSections
        })
        .addDisposableTo(disposeBag)
    }
    
    // MARK: Methods
    
    func synchronize() -> (observableFactory: () -> Observable<Void>, activity: Driver<Bool>) {
        return proposalsStatusSynchronizer.synchronize()
    }
}

fileprivate struct ProposalStatusVersion: Hashable {
    let status: Proposal.Status
    let swiftVersion: String?
    
    var hashValue: Int {
        var hashValue = status.rawValue.hashValue
        
        if let swiftVersion = swiftVersion {
            hashValue = hashValue ^ swiftVersion.hashValue
        }
        
        return hashValue
    }
    
    static func == (lhs: ProposalStatusVersion, rhs: ProposalStatusVersion) -> Bool {
        return lhs.status == rhs.status && lhs.swiftVersion == rhs.swiftVersion
    }
}
